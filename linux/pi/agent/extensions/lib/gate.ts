/**
 * Correr la puerta de merge sin congelar la sesión.
 *
 * La primera versión usaba `execFileSync` con stdout y stderr en pipes. Tenía
 * dos problemas, los dos vistos en vivo:
 *
 * 1. **Es sincrónica.** La puerta tarda minutos (clippy, build de release,
 *    tests y todos los verificadores). Mientras corre, el proceso de pi no
 *    puede dibujar ni leer teclas: la ventana de kitty se ve congelada y el
 *    agente parece colgado.
 * 2. **No vuelve hasta que se cierran los pipes.** Un servidor que algún
 *    verificador deja vivo hereda el pipe de stdout y `execFileSync` espera
 *    para siempre, aunque el script ya haya terminado. Así quedó colgado el
 *    cierre de worktree durante siete minutos.
 *
 * Ahora el comando escribe **directo a un archivo** (un descriptor, no un
 * pipe), se espera con un `await` y, mientras tanto, se lee la cola del archivo
 * para contar por dónde va. Nada puede retener la salida, y el bucle de pi
 * sigue vivo: el spinner anima, se puede escribir y Ctrl+C aborta el turno.
 *
 * El timeout y el abort matan el **grupo de procesos** entero (el comando sale
 * con `detached`, así los hijos que deje un verificador no quedan sueltos).
 */

import { spawn, type ChildProcess } from "node:child_process";
import { closeSync, fstatSync, openSync, readSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export interface ResultadoGate {
  ok: boolean;
  /** Una línea para el agente: verde con el tiempo, o rojo con qué falló. */
  resumen: string;
  /** El mensaje largo (solo cuando hay rojo). */
  mensaje: string;
  segundos: number;
  archivo: string;
}

export interface PedidoGate {
  /** Carpeta donde corre el comando. */
  cwd: string;
  comando: string;
  /** Cuánto puede tardar antes de que lo mate. */
  limiteMs?: number;
  /** Para cortarlo cuando el usuario interrumpe el turno. */
  signal?: AbortSignal;
  /** Se llama en el camino con la última línea y el tiempo transcurrido. */
  progreso?: (linea: string, segundos: number) => void;
}

/** Cuántos bytes de la cola se miran para el resumen y para el progreso. */
const COLA_RESUMEN = 256_000;
const COLA_PROGRESO = 8_192;

export async function correrComando(pedido: PedidoGate): Promise<ResultadoGate> {
  const limiteMs = pedido.limiteMs ?? 2_400_000;
  const archivo = join(
    tmpdir(),
    `pi-gate-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.log`,
  );
  const fd = openSync(archivo, "w");
  const inicio = Date.now();

  let motivo: "timeout" | "abort" | null = null;
  let hijo: ChildProcess;
  try {
    hijo = spawn("bash", ["-lc", pedido.comando], {
      cwd: pedido.cwd,
      // Grupo propio: el timeout y el abort matan también a los nietos.
      detached: true,
      // Nada de pipes: un servidor que quede vivo no puede retener la salida.
      stdio: ["ignore", fd, fd],
      env: { ...process.env },
    });
  } finally {
    closeSync(fd); // el hijo ya tiene su propia copia
  }

  const matar = (): void => {
    if (!hijo.pid) return;
    try {
      process.kill(-hijo.pid, "SIGKILL");
    } catch {
      try {
        hijo.kill("SIGKILL");
      } catch {
        /* se fue solo */
      }
    }
  };

  const temporizador = setTimeout(() => {
    motivo = "timeout";
    matar();
  }, limiteMs);
  const alAbortar = (): void => {
    motivo = "abort";
    matar();
  };
  pedido.signal?.addEventListener("abort", alAbortar, { once: true });

  let ultima = "";
  let ultimoAviso = 0;
  const vigilante = pedido.progreso
    ? setInterval(() => {
        const segundos = Math.floor((Date.now() - inicio) / 1000);
        const linea = ultimaLineaUtil(colaDelArchivo(archivo, COLA_PROGRESO)) ?? ultima;
        // Se avisa cuando cambia lo que está haciendo, y si no cambia, cada 10s
        // igual late: el reloj es lo que distingue «trabajando» de «colgado».
        if (linea === ultima && segundos - ultimoAviso < 10) return;
        ultima = linea;
        ultimoAviso = segundos;
        pedido.progreso?.(linea, segundos);
      }, 1_500)
    : undefined;

  const resultado = await new Promise<{ codigo: number | null; senal: string | null; error?: Error }>(
    (resolver) => {
      hijo.on("error", (error) => resolver({ codigo: null, senal: null, error }));
      hijo.on("close", (codigo, senal) => resolver({ codigo, senal }));
    },
  );

  clearTimeout(temporizador);
  if (vigilante) clearInterval(vigilante);
  pedido.signal?.removeEventListener("abort", alAbortar);

  const segundos = Math.round((Date.now() - inicio) / 1000);
  const texto = colaDelArchivo(archivo, COLA_RESUMEN);

  if (motivo === "timeout") {
    return {
      ok: false,
      segundos,
      archivo,
      resumen: `puerta de merge colgada: la corté a los ${Math.round(limiteMs / 1000)}s`,
      mensaje:
        `la verificación del repo no terminó en ${Math.round(limiteMs / 1000)}s y la corté; ` +
        `la rama no se mergeó y el worktree quedó intacto.\n` +
        `detalle: ${archivo}\n` +
        `Si el gate está roto por el entorno y querés saltearlo igual: PI_SIN_GATE=1.` +
        (texto ? `\n── final de la salida ──\n${colita(texto, 25)}` : ""),
    };
  }

  if (motivo === "abort") {
    return {
      ok: false,
      segundos,
      archivo,
      resumen: "puerta de merge interrumpida",
      mensaje:
        "interrumpiste el turno mientras corría la verificación; la rama no se mergeó y el " +
        `worktree quedó intacto.\ndetalle: ${archivo}`,
    };
  }

  if (resultado.error) {
    return {
      ok: false,
      segundos,
      archivo,
      resumen: "puerta de merge no arrancó",
      mensaje: `no pude correr \`${pedido.comando}\`: ${resultado.error.message}`,
    };
  }

  if (resultado.codigo === 0) {
    const fin = ultimaLineaUtil(texto) ?? "verificación en verde";
    return {
      ok: true,
      segundos,
      archivo,
      resumen: `puerta de merge OK en ${formatearSegundos(segundos)}: ${fin}`,
      mensaje: "",
    };
  }

  const fallas = lineasDeFalla(texto);
  const codigo = resultado.codigo ?? `señal ${resultado.senal ?? "?"}`;
  return {
    ok: false,
    segundos,
    archivo,
    resumen: `puerta de merge en rojo${fallas ? `: ${fallas.replace(/\n+/g, " · ").slice(0, 300)}` : ` (${codigo})`}`,
    mensaje:
      `la verificación del repo falló (${pedido.comando}); la rama no se mergeó y el worktree quedó intacto.\n` +
      `detalle: ${archivo}\n` +
      (fallas ? `── qué falló ──\n${fallas}\n` : "") +
      `Arreglá lo que falla y volvé a cerrar. Si el gate está roto por el entorno y querés saltearlo igual: PI_SIN_GATE=1.\n` +
      `── final de la salida ──\n${colita(texto, 25)}`,
  };
}

/** Los últimos bytes del registro, sin cargar todo el archivo en memoria. */
export function colaDelArchivo(archivo: string, bytes: number): string {
  try {
    const fd = openSync(archivo, "r");
    try {
      const tamano = fstatSync(fd).size;
      const desde = Math.max(0, tamano - bytes);
      const buffer = Buffer.alloc(tamano - desde);
      if (buffer.length === 0) return "";
      readSync(fd, buffer, 0, buffer.length, desde);
      return buffer.toString("utf8");
    } finally {
      closeSync(fd);
    }
  } catch {
    return "";
  }
}

const SIN_COLORES = /\u001b\[[0-9;]*[A-Za-z]/g;

export function ultimaLineaUtil(salida: string): string | undefined {
  return salida
    .split("\n")
    .map((linea) => linea.replace(SIN_COLORES, "").trim())
    .filter(Boolean)
    .at(-1);
}

/** Las líneas que dicen qué falló, arriba y cortas: es lo primero que se lee. */
export function lineasDeFalla(texto: string): string {
  const limpias = texto
    .split("\n")
    .map((linea) => linea.replace(SIN_COLORES, "").trimEnd())
    .filter((linea) => /✗|FALLÓ|^error|^--- FAIL|panicked|^make.*\*\*\*/.test(linea));
  if (!limpias.length) return "";
  const unicas = [...new Set(limpias)].slice(0, 12);
  return unicas.join("\n");
}

export function colita(texto: string, lineas: number): string {
  return texto
    .split("\n")
    .map((linea) => linea.replace(SIN_COLORES, ""))
    .slice(-lineas)
    .join("\n");
}

export function formatearSegundos(segundos: number): string {
  if (segundos < 60) return `${segundos}s`;
  const minutos = Math.floor(segundos / 60);
  const resto = segundos % 60;
  return resto ? `${minutos}m ${resto}s` : `${minutos}m`;
}
