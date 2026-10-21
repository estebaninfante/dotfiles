/**
 * auditor — herramientas de SOLO LECTURA para que el modelo frontera pueda
 * auditar el problema en vez de opinar sobre el resumen de otro.
 *
 * El consultor no ejecuta código ni escribe: lee archivos, busca símbolos y
 * mira el diff. Eso alcanza para encontrar la causa de la mayoría de las trabas
 * y mantiene el costo acotado: cada salida se recorta y hay un tope de llamadas.
 *
 * Todo se restringe al repo (`cwd`): nada de `/etc`, llaves, `.env` ni rutas
 * con `..`. Los comandos de git son un enum cerrado, no una shell libre.
 */

import { execFile } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { basename, isAbsolute, relative, resolve, sep } from "node:path";

export interface HerramientaAuditor {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}

/** Tope de la auditoría: barato y suficiente para diagnosticar. */
export const LIMITES_AUDITORIA = {
  /** Rondas de conversación con el frontera. */
  rondas: 4,
  /** Llamadas a herramientas en total. */
  llamadas: 6,
  /** Tiempo total de la auditoría. */
  ms: 75_000,
  /** Tokens de entrada+salida acumulados antes de cortar. */
  tokens: 30_000,
  /** Bytes por resultado de herramienta. */
  salida: 8_000,
} as const;

export const HERRAMIENTAS_AUDITOR: HerramientaAuditor[] = [
  {
    name: "read_file",
    description:
      "Lee un archivo de texto del repo. Devuelve las líneas numeradas. Usalo para ver el código involucrado en el error.",
    parameters: {
      type: "object",
      properties: {
        path: { type: "string", description: "Ruta relativa al repo" },
        from: { type: "integer", description: "Primera línea (1-based)" },
        lines: { type: "integer", description: "Cuántas líneas leer (máx 300)" },
      },
      required: ["path"],
      additionalProperties: false,
    },
  },
  {
    name: "search_repo",
    description:
      "Busca un texto o expresión regular en el repo y devuelve coincidencias con archivo:línea. Usalo para ubicar símbolos, mensajes de error o llamadas.",
    parameters: {
      type: "object",
      properties: {
        pattern: { type: "string", description: "Texto o regex a buscar" },
        path: { type: "string", description: "Subcarpeta opcional donde buscar" },
        glob: { type: "string", description: "Filtro de archivos, ej. '*.ts'" },
      },
      required: ["pattern"],
      additionalProperties: false,
    },
  },
  {
    name: "git_review",
    description:
      "Mira el estado, el diff o los últimos commits del repo. Usalo para ver qué cambió y qué quedó a medias.",
    parameters: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["status", "diff", "log"], description: "Qué revisar" },
        path: { type: "string", description: "Ruta opcional para acotar el diff" },
      },
      required: ["action"],
      additionalProperties: false,
    },
  },
];

const NOMBRES_PROHIBIDOS = /(^|\/)(\.env(\..*)?|\.npmrc|\.netrc|auth\.json|credentials.*|id_[a-z0-9]+|.*\.(pem|key|p12|pfx))$/i;

/** ¿La ruta queda dentro del repo y no es un secreto? */
export function rutaPermitida(
  cwd: string,
  ruta: string,
): { ok: true; absoluta: string; relativa: string } | { ok: false; error: string } {
  if (!ruta || typeof ruta !== "string") return { ok: false, error: "falta la ruta" };
  const absoluta = resolve(cwd, ruta);
  const base = resolve(cwd);
  const dentro = absoluta === base || absoluta.startsWith(base + sep);
  if (!dentro) return { ok: false, error: "la ruta está fuera del repo" };
  const relativa = relative(base, absoluta) || ".";
  if (relativa.split(sep).some((parte) => parte === "..")) return { ok: false, error: "ruta inválida" };
  if (NOMBRES_PROHIBIDOS.test(relativa) || NOMBRES_PROHIBIDOS.test(basename(absoluta))) {
    return { ok: false, error: "archivo reservado (secretos): no se puede leer" };
  }
  if (relativa.split(sep).some((parte) => parte === ".git")) {
    return { ok: false, error: "no se lee .git" };
  }
  return { ok: true, absoluta, relativa };
}

/** Recorta una salida y avisa que quedó cortada. */
export function recortarSalida(texto: string, max = LIMITES_AUDITORIA.salida): string {
  if (texto.length <= max) return texto;
  return `${texto.slice(0, max - 60)}\n… (salida recortada; pedí una parte más chica si hace falta)`;
}

function correr(
  comando: string,
  args: string[],
  cwd: string,
): Promise<{ ok: boolean; salida: string }> {
  return new Promise((resolver) => {
    execFile(
      comando,
      args,
      { cwd, timeout: 8_000, maxBuffer: 2 * 1024 * 1024, encoding: "utf8" },
      (error, stdout, stderr) => {
        if (error && !stdout && !stderr) {
          resolver({ ok: false, salida: String((error as { message?: string }).message ?? error) });
          return;
        }
        const codigo = (error as { code?: number } | null)?.code;
        // ripgrep devuelve 1 cuando no encontró nada: no es un error.
        const ok = !error || codigo === 1 || codigo === 0;
        resolver({ ok, salida: `${stdout ?? ""}${stderr ?? ""}`.trim() });
      },
    );
  });
}

function leerArchivo(cwd: string, args: Record<string, unknown>): Promise<{ texto: string; isError: boolean }> {
  const ruta = rutaPermitida(cwd, String(args.path ?? ""));
  if (!ruta.ok) return Promise.resolve({ texto: `error: ${ruta.error}`, isError: true });
  try {
    const stats = statSync(ruta.absoluta);
    if (!stats.isFile()) return Promise.resolve({ texto: "error: no es un archivo", isError: true });
    if (stats.size > 1_500_000) return Promise.resolve({ texto: "error: archivo demasiado grande", isError: true });
    const contenido = readFileSync(ruta.absoluta, "utf8");
    const todas = contenido.split("\n");
    const desde = Math.max(1, Number(args.from) || 1);
    const cuantas = Math.min(300, Math.max(1, Number(args.lines) || 160));
    const hasta = Math.min(todas.length, desde + cuantas - 1);
    const cuerpo = todas
      .slice(desde - 1, hasta)
      .map((linea, i) => `${String(desde + i).padStart(5)} | ${linea}`)
      .join("\n");
    return Promise.resolve({
      texto: recortarSalida(`${ruta.relativa} (líneas ${desde}-${hasta} de ${todas.length})\n${cuerpo}`),
      isError: false,
    });
  } catch (error) {
    return Promise.resolve({
      texto: `error leyendo ${ruta.relativa}: ${String((error as { message?: string }).message ?? error)}`,
      isError: true,
    });
  }
}

async function buscar(cwd: string, args: Record<string, unknown>): Promise<{ texto: string; isError: boolean }> {
  const patron = String(args.pattern ?? "").trim();
  if (!patron) return { texto: "error: falta el patrón", isError: true };
  const argsRg = [
    "--line-number",
    "--no-heading",
    "--color",
    "never",
    "--max-columns",
    "300",
    "--max-count",
    "40",
    "--glob",
    "!.env*",
    "--glob",
    "!*.pem",
    "--glob",
    "!*.key",
    "--glob",
    "!node_modules",
    "--glob",
    "!.git",
  ];
  if (args.glob) argsRg.push("--glob", String(args.glob));
  let destino = ".";
  if (args.path) {
    const ruta = rutaPermitida(cwd, String(args.path));
    if (!ruta.ok) return { texto: `error: ${ruta.error}`, isError: true };
    destino = ruta.relativa;
  }
  argsRg.push("--", patron, destino);
  const resultado = await correr("rg", argsRg, cwd);
  if (!resultado.salida) {
    return {
      texto: resultado.ok ? "sin coincidencias" : `error: ${resultado.salida}`,
      isError: !resultado.ok,
    };
  }
  return { texto: recortarSalida(resultado.salida), isError: !resultado.ok };
}

async function revisarGit(cwd: string, args: Record<string, unknown>): Promise<{ texto: string; isError: boolean }> {
  const accion = String(args.action ?? "");
  const argsGit = ["-C", cwd];
  if (accion === "status") {
    argsGit.push("status", "--short", "--branch");
  } else if (accion === "log") {
    argsGit.push("log", "-8", "--oneline", "--decorate");
  } else if (accion === "diff") {
    let ruta: string | undefined;
    if (args.path) {
      const permitida = rutaPermitida(cwd, String(args.path));
      if (!permitida.ok) return { texto: `error: ${permitida.error}`, isError: true };
      ruta = permitida.relativa;
    }
    argsGit.push("diff", "--stat", "--patch", "--no-color");
    if (ruta) argsGit.push("--", ruta);
  } else {
    return { texto: "error: action debe ser status, diff o log", isError: true };
  }
  const resultado = await correr("git", argsGit, cwd);
  return {
    texto: resultado.salida ? recortarSalida(resultado.salida) : "sin cambios",
    isError: !resultado.ok,
  };
}

/** Ejecuta una herramienta de auditoría. Nunca tira: devuelve texto de error. */
export async function ejecutarHerramienta(
  cwd: string,
  nombre: string,
  argumentos: unknown,
): Promise<{ texto: string; isError: boolean }> {
  const args = (argumentos && typeof argumentos === "object" ? argumentos : {}) as Record<string, unknown>;
  try {
    if (nombre === "read_file") return await leerArchivo(cwd, args);
    if (nombre === "search_repo") return await buscar(cwd, args);
    if (nombre === "git_review") return await revisarGit(cwd, args);
    return { texto: `error: herramienta desconocida ${nombre}`, isError: true };
  } catch (error) {
    return { texto: `error: ${String((error as { message?: string })?.message ?? error)}`, isError: true };
  }
}
