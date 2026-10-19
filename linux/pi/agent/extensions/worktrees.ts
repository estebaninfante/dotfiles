/**
 * Worktrees obligatorios: una versión del código por agente.
 *
 * Dos agentes en la misma carpeta se pisan: uno borra el archivo que el otro
 * está leyendo, un `git add -A` se lleva trabajo ajeno y el árbol queda sucio
 * sin saber de quién es cada cambio. Por eso, si el repo lo pide, cada agente
 * trabaja en su propio git worktree (una carpeta y una rama propias) y lo
 * mergea al terminar.
 *
 * Reglas por repo en `~/.pi/agent/worktrees.json`:
 *
 * - `main`: worktree obligatorio; la base y el destino del merge son la rama
 *   principal (o la que diga `rama`). Para proyectos chicos que viven en main.
 * - `developing`: worktree obligatorio; base y destino son la rama de
 *   desarrollo (`developing` o la que diga `rama`).
 * - `directo`: se edita en el lugar, sin worktree (dotfiles, configs que la
 *   máquina lee del propio repo).
 *
 * Lo que hace la extensión:
 *
 * 1. Pone las reglas en el system prompt de cada turno, con el repo actual y
 *    la base concreta (no hay que adivinar).
 * 2. Bloquea write/edit y los comandos de bash que escriben en la copia
 *    principal, con un motivo que dice cómo seguir.
 * 3. Le da a cada subagente su propio worktree (mutando la llamada antes de
 *    que arranque) y lo poda si quedó vacío.
 * 4. Expone la tool `worktree` (abrir / lista / cerrar) para que abrir y
 *    mergear sea un paso explícito y no un `git` a mano.
 * 5. `/worktrees libre` abre el candado para la sesión actual.
 *
 * Los helpers puros viven en `lib/ramas.ts`.
 */

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { Type } from "typebox";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

import {
  comandoMutaRepo,
  configNormalizada,
  dentroDe,
  idCorto,
  normalizar,
  politicaDe,
  ramaDe,
  rutaWorktree,
  type Config,
  type Politica,
} from "./lib/ramas.ts";

const ARCHIVO = process.env.PI_RAMAS ?? join(homedir(), ".pi", "agent", "worktrees.json");

interface Datos {
  /** Raíz del checkout donde está parado el agente. */
  raiz: string;
  /** Copia principal del repo (aunque el agente esté en un worktree). */
  principal: string;
  esWorktree: boolean;
  rama: string | null;
}

interface Worktree {
  ruta: string;
  rama: string;
  base: string;
  repo: string;
  creado: boolean;
}

/** Worktrees abiertos por llamadas a subagentes, para poder podarlos. */
const prestados = new Map<string, Worktree[]>();
let libre = process.env.PI_SIN_WORKTREES === "1";

// ------------------------------------------------------------------- git

function git(dir: string, args: string[]): string {
  return execFileSync("git", ["-C", dir, ...args], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    timeout: 60_000,
  }).trim();
}

/** Igual que `git` pero null cuando el comando falla (para ramas que no existen). */
function tal(dir: string, args: string[]): string | null {
  try {
    return git(dir, args);
  } catch {
    return null;
  }
}

function existeRama(repo: string, rama: string): boolean {
  return Boolean(tal(repo, ["rev-parse", "--verify", "--quiet", `refs/heads/${rama}`]));
}

function datosRepo(dir: string): Datos | null {
  const raiz = tal(dir, ["rev-parse", "--show-toplevel"]);
  if (!raiz) return null;
  const gitDir = normalizar(tal(dir, ["rev-parse", "--git-dir"]) ?? "", raiz);
  const comun = normalizar(tal(dir, ["rev-parse", "--git-common-dir"]) ?? "", raiz);
  const esWorktree = Boolean(comun) && gitDir !== comun;
  return {
    raiz: normalizar(raiz),
    principal: esWorktree ? dirname(comun) : normalizar(raiz),
    esWorktree,
    rama: tal(raiz, ["symbolic-ref", "--short", "HEAD"]),
  };
}

function ramaPrincipal(repo: string): string {
  for (const nombre of ["main", "master"]) {
    if (existeRama(repo, nombre)) return nombre;
  }
  const actual = tal(repo, ["symbolic-ref", "--short", "HEAD"]);
  if (actual && existeRama(repo, actual)) return actual;
  const primera = (tal(repo, ["for-each-ref", "--format=%(refname:short)", "refs/heads"]) ?? "")
    .split("\n")
    .filter(Boolean)[0];
  if (primera) return primera;
  throw new Error(`el repo ${repo} no tiene ramas: no hay de dónde abrir el worktree`);
}

/** La rama base real: la configurada o, si no hay, la principal del repo. */
function baseEfectiva(datos: Datos, politica: Politica): string {
  if (politica.base) {
    if (existeRama(datos.principal, politica.base)) return politica.base;
    throw new Error(
      `la rama base "${politica.base}" no existe en ${datos.principal}. ` +
        `Creala o corregí ~/.pi/agent/worktrees.json (el flujo ${politica.flujo} de ${politica.repo}).`,
    );
  }
  return ramaPrincipal(datos.principal);
}

// ---------------------------------------------------------------- estado

function leerConfig(): Config {
  try {
    return configNormalizada(JSON.parse(readFileSync(ARCHIVO, "utf8")));
  } catch {
    return configNormalizada({});
  }
}

function situacion(dir: string): { datos: Datos; politica: Politica } | null {
  const datos = datosRepo(dir);
  if (!datos) return null;
  return { datos, politica: politicaDe(leerConfig(), basename(datos.principal)) };
}

/** Repo de una ruta que puede no existir todavía: sube hasta el primer directorio real. */
function repoDeRuta(ruta: string): { datos: Datos; politica: Politica } | null {
  let candidato = normalizar(ruta);
  for (let i = 0; i < 12 && candidato !== "/"; i += 1) {
    if (existsSync(candidato)) return situacion(datosRepo(candidato) ? candidato : dirname(candidato));
    candidato = dirname(candidato);
  }
  return null;
}

// ------------------------------------------------------------- worktrees

function abrirWorktree(dir: string, id: string, desde?: string): Worktree {
  const actual = situacion(dir);
  if (!actual) throw new Error(`no es un repo git: ${dir}`);
  const { datos, politica } = actual;
  if (!politica.exigeWorktree) {
    throw new Error(
      `${politica.repo} usa flujo directo: se edita en el lugar (${datos.principal}), sin worktree.`,
    );
  }
  const config = leerConfig();
  const rama = ramaDe(config, id);
  const ruta = rutaWorktree(datos.principal, id);
  const base = desde ? (tal(datos.principal, ["rev-parse", "--verify", `${desde}^{commit}`]) ?? baseEfectiva(datos, politica)) : baseEfectiva(datos, politica);

  if (existsSync(ruta)) {
    const previo = datosRepo(ruta);
    if (previo?.esWorktree) {
      return { ruta: normalizar(ruta), rama: previo.rama ?? rama, base, repo: datos.principal, creado: false };
    }
    throw new Error(`la ruta ${ruta} existe y no es un worktree: revisala a mano`);
  }

  if (existeRama(datos.principal, rama)) {
    git(datos.principal, ["worktree", "add", ruta, rama]);
  } else {
    git(datos.principal, ["worktree", "add", "-b", rama, ruta, base]);
  }
  return { ruta: normalizar(ruta), rama, base, repo: datos.principal, creado: true };
}

function listarWorktrees(dir: string): string {
  const actual = situacion(dir);
  if (!actual) throw new Error(`no es un repo git: ${dir}`);
  return git(actual.datos.principal, ["worktree", "list"]);
}

function commitsAdelante(ruta: string, base: string): number {
  const salida = tal(ruta, ["rev-list", "--count", `${base}..HEAD`]);
  return Number(salida ?? 0) || 0;
}

function cerrarWorktree(ruta: string, opciones: { borrarRama?: boolean; base?: string } = {}): string {
  const datos = datosRepo(ruta);
  if (!datos) throw new Error(`no es un repo git: ${ruta}`);
  if (!datos.esWorktree) throw new Error(`${datos.raiz} es la copia principal, no un worktree`);
  const rama = datos.rama;
  if (!rama) throw new Error(`${datos.raiz} no tiene rama (HEAD suelto)`);

  const sucio = git(datos.raiz, ["status", "--porcelain"]);
  if (sucio) {
    throw new Error(`quedan cambios sin commitear en ${datos.raiz}:\n${sucio}\nCommitéalos antes de cerrar.`);
  }

  const actual = situacion(datos.principal);
  const base = opciones.base ?? (actual ? baseEfectiva(actual.datos, actual.politica) : ramaPrincipal(datos.principal));
  const enPrincipal = tal(datos.principal, ["symbolic-ref", "--short", "HEAD"]);
  if (enPrincipal !== base) {
    throw new Error(
      `la copia principal está en "${enPrincipal ?? "?"}", no en la base "${base}". ` +
        `Cambiala a ${base} y volvé a cerrar.`,
    );
  }

  const lineas: string[] = [];
  const adelante = commitsAdelante(datos.raiz, base);
  if (adelante > 0) {
    try {
      git(datos.principal, ["merge", "--no-ff", "-m", `merge(${base}): ${rama}`, rama]);
      lineas.push(`mergeado ${rama} -> ${base} (${adelante} commit(s))`);
    } catch (error) {
      tal(datos.principal, ["merge", "--abort"]);
      throw new Error(`el merge de ${rama} en ${base} falló y lo aborté: ${mensajeDe(error)}`);
    }
  } else {
    lineas.push(`${rama} no tenía commits nuevos sobre ${base}`);
  }

  git(datos.principal, ["worktree", "remove", datos.raiz]);
  lineas.push(`worktree borrado: ${datos.raiz}`);
  if (opciones.borrarRama !== false) {
    const borrada = tal(datos.principal, ["branch", "-d", rama]);
    lineas.push(borrada ? `rama borrada: ${rama}` : `la rama ${rama} quedó (git no la dio por mergeada)`);
  }
  return lineas.join("\n");
}

/** Worktrees de subagentes que no aportaron nada: se van solos. */
function podar(abiertos: Worktree[]): string[] {
  const hechos: string[] = [];
  for (const wt of abiertos) {
    if (!existsSync(wt.ruta)) continue;
    const sucio = tal(wt.ruta, ["status", "--porcelain"]);
    if (sucio === null) continue;
    if (sucio || commitsAdelante(wt.ruta, wt.base) > 0) {
      hechos.push(`queda vivo (tiene trabajo): ${wt.ruta} (${wt.rama})`);
      continue;
    }
    const fuera = tal(wt.repo, ["worktree", "remove", wt.ruta]);
    tal(wt.repo, ["branch", "-d", wt.rama]);
    if (fuera !== null) hechos.push(`podado vacío: ${wt.ruta}`);
  }
  return hechos;
}

function mensajeDe(error: unknown): string {
  const texto = error instanceof Error ? error.message : String(error);
  const conStderr = error as { stderr?: Buffer | string };
  const detalle = conStderr?.stderr ? String(conStderr.stderr).trim() : "";
  return [texto.split("\n")[0], detalle].filter(Boolean).join(" · ");
}

// ----------------------------------------------------------------- texto

function textoPolitica(datos: Datos | null, politica: Politica): string {
  if (!datos) return "";
  const nombre = basename(datos.principal);
  if (libre) {
    return `## Worktrees\n\nRepo **${nombre}** (\`${datos.principal}\`): el candado de worktrees está desactivado en esta sesión (\`/worktrees volver\` lo reactiva).`;
  }
  if (politica.flujo === "directo") {
    return `## Worktrees\n\nRepo **${nombre}**: flujo directo, se edita acá en el lugar (\`${datos.principal}\`). No hace falta worktree.`;
  }
  const base = politica.base ?? "la rama principal";
  if (datos.esWorktree) {
    return [
      `## Worktrees`,
      ``,
      `Estás en el worktree \`${datos.raiz}\` (rama **${datos.rama ?? "?"}**, base ${base}) del repo **${nombre}**.`,
      `Trabajá y commiteá acá. Al terminar y verificar: tool \`worktree\` con \`{accion:"cerrar", ruta:"${datos.raiz}"}\` (mergea a ${base}, borra el worktree).`,
      `Los subagentes que lances reciben su propio worktree.`,
    ].join("\n");
  }
  return [
    `## Worktrees: una versión por agente`,
    ``,
    `Repo **${nombre}** (\`${datos.principal}\`), flujo **${politica.flujo}**, base **${base}**.`,
    `Esta carpeta es la copia principal: no se edita. Cada agente trabaja en su propio worktree.`,
    ``,
    `1. Antes de tocar código: tool \`worktree\` con \`{accion:"abrir", id:"<slug de la tarea>"}\`.`,
    `   Devuelve \`ruta\` y \`rama\` (sale de ${base}); queda en \`${dirname(datos.principal)}/.rig-worktrees/${nombre}/<id>\`.`,
    `2. Editá y corré comandos con esa ruta (cada \`bash\` empieza en el cwd original: usá \`cd\` a la ruta del worktree).`,
    `3. Commiteá en la rama del worktree.`,
    `4. Verificá (tests / verificadores del repo) y recién ahí cerrá: \`{accion:"cerrar", ruta}\`.`,
    `   Eso mergea a ${base}, borra el worktree y la rama.`,
    ``,
    `Los subagentes reciben su worktree automáticamente. Para tocar la copia principal a propósito: \`/worktrees libre\`.`,
  ].join("\n");
}

function motivoBloqueo(datos: Datos, politica: Politica, que: string): string {
  const base = politica.base ?? "la rama principal";
  return (
    `${que} en la copia principal de ${politica.repo} (\`${datos.principal}\`), y este repo pide worktree ` +
    `(flujo ${politica.flujo}, base ${base}). Abrí uno con la tool \`worktree\` ` +
    `{accion:"abrir", id:"<slug>", repo:"${datos.principal}"}, trabajá ahí y al final ` +
    `{accion:"cerrar", ruta}. Si de verdad hay que tocar la principal, \`/worktrees libre\` ` +
    `(o PI_SIN_WORKTREES=1).`
  );
}

// ------------------------------------------------------------ subagentes

function anotar(tarea: string, wt: Worktree): string {
  return (
    `🌿 Trabajás en el worktree \`${wt.ruta}\` (rama ${wt.rama}, base ${wt.base}) del repo ` +
    `${basename(wt.repo)}. Esa es tu carpeta: no toques ${wt.repo}. Commiteá en tu rama.\n\n${tarea}`
  );
}

/** Le da un worktree propio a cada tarea del subagente, antes de que arranque. */
function prepararSubagentes(entrada: Record<string, unknown>, ctx: ExtensionContext): Worktree[] {
  const abiertos: Worktree[] = [];
  const preparar = (item: Record<string, unknown>, idBase: string): void => {
    const cwd = typeof item.cwd === "string" ? item.cwd : ctx.cwd;
    const actual = situacion(cwd);
    if (!actual || !actual.politica.exigeWorktree || actual.datos.esWorktree) return;
    const agente = typeof item.agent === "string" ? item.agent : "agente";
    try {
      const wt = abrirWorktree(cwd, `${idBase}-${agente}`, actual.datos.raiz);
      item.cwd = wt.ruta;
      item.task = anotar(String(item.task ?? ""), wt);
      abiertos.push(wt);
    } catch {
      /* si no se puede abrir, el candado de write/edit igual frena la edición */
    }
  };

  const lista = (valor: unknown) => (Array.isArray(valor) ? (valor as Record<string, unknown>[]) : null);
  const cadena = lista(entrada.chain);
  const paralelo = lista(entrada.tasks);
  if (cadena) {
    for (const [indice, paso] of cadena.entries()) preparar(paso, `cadena-${indice + 1}`);
    if (cadena.length > 0) {
      const primero = cadena[0].cwd;
      for (const paso of cadena.slice(1)) if (typeof primero === "string") paso.cwd = primero;
    }
  } else if (paralelo) {
    for (const tarea of paralelo) preparar(tarea, idCorto(String(tarea.task ?? "tarea")));
  } else if (typeof entrada.agent === "string") {
    preparar(entrada, idCorto(String(entrada.task ?? "tarea")));
  }
  if (abiertos.length) ctx.ui.notify(`Subagentes en worktrees: ${abiertos.map((w) => w.ruta).join(", ")}`, "info");
  return abiertos;
}

// ------------------------------------------------------------------- pi

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (_event, ctx) => {
    const actual = situacion(ctx.cwd);
    if (!actual) return;
    const { datos, politica } = actual;
    if (!politica.exigeWorktree || datos.esWorktree) return;
    ctx.ui.notify(
      `Estás en la copia principal de ${politica.repo}: para tocar código abrí un worktree ` +
        `(tool worktree) — base ${politica.base ?? "principal"}.`,
      "warning",
    );
  });

  pi.on("before_agent_start", (event, ctx) => {
    const actual = situacion(ctx.cwd);
    const texto = actual ? textoPolitica(actual.datos, actual.politica) : "";
    if (texto) event.systemPromptOptions.sections.worktrees = texto;
    else delete event.systemPromptOptions.sections.worktrees;
  });

  pi.on("tool_call", (event, ctx) => {
    const entrada = event.input as Record<string, unknown>;

    if (event.toolName === "subagent") {
      const abiertos = prepararSubagentes(entrada, ctx);
      if (abiertos.length) prestados.set(String(event.toolCallId ?? "subagent"), abiertos);
      return undefined;
    }

    if (libre) return undefined;

    if (event.toolName === "write" || event.toolName === "edit") {
      const destino = String(entrada.path ?? "");
      if (!destino) return undefined;
      const absoluta = normalizar(destino, ctx.cwd);
      const actual = repoDeRuta(absoluta);
      if (!actual || !actual.politica.exigeWorktree || actual.datos.esWorktree) return undefined;
      if (!dentroDe(actual.datos.principal, absoluta)) return undefined;
      return { block: true, reason: motivoBloqueo(actual.datos, actual.politica, `Escritura de ${destino}`) };
    }

    if (event.toolName === "bash") {
      const actual = situacion(ctx.cwd);
      if (!actual || !actual.politica.exigeWorktree || actual.datos.esWorktree) return undefined;
      const { datos, politica } = actual;
      const comando = String(entrada.command ?? "");
      const motivo = comandoMutaRepo(comando, { repo: datos.principal, cwd: ctx.cwd, home: homedir() });
      if (!motivo) return undefined;
      return { block: true, reason: motivoBloqueo(datos, politica, `Comando que escribe (${motivo})`) };
    }

    return undefined;
  });

  pi.on("tool_result", (event, ctx) => {
    const abiertos = prestados.get(String(event.toolCallId ?? ""));
    if (!abiertos) return;
    prestados.delete(String(event.toolCallId ?? ""));
    const cambios = podar(abiertos);
    if (cambios.length) ctx.ui.notify(cambios.join("\n"), "info");
  });

  pi.registerTool({
    name: "worktree",
    label: "Worktree",
    description:
      "Abre, lista o cierra el worktree (carpeta + rama propias) de este agente. " +
      'abrir: {accion:"abrir", id:"slug"} devuelve ruta y rama. ' +
      'cerrar: {accion:"cerrar", ruta} commitea lo pendiente ya hecho, mergea a la base y borra el worktree.',
    promptSnippet: "Trabajar en un worktree propio en vez de la copia principal",
    promptGuidelines: [
      "Antes de tocar código en un repo con flujo main/developing, abrí un worktree con la tool " +
        "`worktree` y trabajá ahí; la copia principal queda intacta.",
      "Al terminar y verificar, cerrá el worktree con `worktree` {accion:\"cerrar\", ruta} para " +
        "mergear a la base y limpiar.",
    ],
    parameters: Type.Object({
      accion: Type.Union([Type.Literal("abrir"), Type.Literal("lista"), Type.Literal("cerrar")], {
        description: "abrir | lista | cerrar",
      }),
      id: Type.Optional(Type.String({ description: "Slug de la tarea; nombra la carpeta y la rama (abrir)" })),
      repo: Type.Optional(
        Type.String({ description: "Ruta dentro del repo, cuando el cwd no es el repo (abrir)" }),
      ),
      ruta: Type.Optional(Type.String({ description: "Ruta del worktree a cerrar (cerrar)" })),
      desde: Type.Optional(
        Type.String({ description: "Ref de la que sale la rama nueva (abrir). Por defecto, la base del repo." }),
      ),
      conservarRama: Type.Optional(Type.Boolean({ description: "No borrar la rama al cerrar" })),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      try {
        if (params.accion === "lista") {
          return { content: [{ type: "text", text: listarWorktrees(ctx.cwd) }], details: {} };
        }
        if (params.accion === "cerrar") {
          const ruta = String(params.ruta ?? "");
          if (!ruta) {
            return {
              content: [{ type: "text", text: "Falta `ruta`: cuál worktree cerrar." }],
              details: {},
              isError: true,
            };
          }
          const texto = cerrarWorktree(normalizar(ruta, ctx.cwd), {
            borrarRama: params.conservarRama !== true,
          });
          return { content: [{ type: "text", text: texto }], details: { ruta } };
        }
        const wt = abrirWorktree(normalizar(String(params.repo ?? ""), ctx.cwd), String(params.id ?? "trabajo"), params.desde);
        return {
          content: [
            {
              type: "text",
              text:
                `${wt.creado ? "Worktree creado" : "Worktree ya estaba"}: ${wt.ruta}\n` +
                `rama: ${wt.rama}\nbase: ${wt.base}\nrepo: ${wt.repo}\n\n` +
                `Trabajá con \`cd ${wt.ruta}\` en cada comando. Al terminar: worktree {accion:"cerrar", ruta:"${wt.ruta}"}.`,
            },
          ],
          details: { ...wt },
        };
      } catch (error) {
        return {
          content: [{ type: "text", text: `No pude: ${mensajeDe(error)}` }],
          details: {},
          isError: true,
        };
      }
    },
  });

  pi.registerCommand("worktrees", {
    description: "Muestra el flujo del repo y abre/cierra el candado (/worktrees libre | volver)",
    handler: async (args, ctx) => {
      const pedido = String(args ?? "").trim().toLowerCase();
      if (pedido === "libre" || pedido === "off") {
        libre = true;
        ctx.ui.notify("Candado de worktrees desactivado en esta sesión.", "warning");
        return;
      }
      if (pedido === "volver" || pedido === "on") {
        libre = false;
        ctx.ui.notify("Candado de worktrees activo.", "info");
        return;
      }
      const actual = situacion(ctx.cwd);
      if (!actual) {
        ctx.ui.notify(`No estás dentro de un repo git (${ctx.cwd}).`, "info");
        return;
      }
      const { datos, politica } = actual;
      const lineas = [
        `repo: ${politica.repo} (${datos.principal})`,
        `flujo: ${politica.flujo} — base ${politica.base ?? ramaPrincipal(datos.principal)}`,
        `worktree obligatorio: ${politica.exigeWorktree && !libre ? "sí" : "no"}`,
        `dónde estás: ${datos.esWorktree ? `worktree (rama ${datos.rama})` : "copia principal"}`,
        `worktrees abiertos:\n${listarWorktrees(datos.principal)}`,
      ];
      ctx.ui.notify(lineas.join("\n"), "info");
    },
  });
}
