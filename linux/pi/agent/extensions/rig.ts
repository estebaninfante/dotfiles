/**
 * rig — las reglas de trabajo del usuario, siempre presentes.
 *
 * Hace cuatro cosas:
 *
 * 1. **Cola de revisión humana.** Cuando el agente crea una skill o un agente
 *    (o cualquier artefacto que necesite ojo humano), lo registra con
 *    `pedir_revision_humana`. Queda pendiente hasta que el usuario lo revise.
 *    Al arrancar cada sesión, si hay pendientes, avisa. `/revisiones` lista y
 *    permite resolver.
 *
 * 2. **Método de software.** Inyecta en el system prompt, en cada turno, cómo
 *    se construye software acá: árbol de features, verificadores deterministas
 *    por feature, correr la verificación antes de publicar, rastro de
 *    decisiones, y hacerlo fácil de escalar para agentes.
 *
 * 3. **Regla de skills/agentes.** Instalar de inmediato y pedir revisión humana.
 *
 * 4. **Tickets y trazas.** Un agente vivo = un ticket raíz abierto (su sesión).
 *    Cada pedido del usuario abre un subticket; cada delegación del agente abre
 *    otro subticket. Todo queda en un árbol (`~/.local/share/pi/tareas.json`),
 *    visible con las tools `tarea`/`tareas` y en `/tareas`, `/traza`, y además
 *    en Markdown legible (`~/.local/share/pi/trazas/<raíz>.md`) para que el
 *    usuario siga el trazo sin leer JSON.
 *
 * Los pendientes viven en `~/.local/share/pi/revisiones.json`, las tareas en
 * `~/.local/share/pi/tareas.json` y las trazas en `~/.local/share/pi/trazas/`
 * (configurable con PI_RIG_DIR).
 */

import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmdirSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join } from "node:path";
import { Type } from "typebox";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  idTarea,
  recortar,
  resumenEntrada,
  tituloDePedido,
} from "./lib/pensamiento.ts";
import {
  deLaSesion,
  descendientesDe,
  esRaiz,
  indiceMarkdown,
  lineasArbol,
  markdownTraza,
  raicesDe,
  raizDe,
  textoTraza,
  type EstadoTarea,
  type Paso,
  type Tarea,
  type TipoTarea,
} from "./lib/trazas.ts";

const DIR = process.env.PI_RIG_DIR ?? join(homedir(), ".local", "share", "pi");
const ARCHIVO = join(DIR, "revisiones.json");
const TAREAS = join(DIR, "tareas.json");
const TRAZAS = join(DIR, "trazas");
const MAX_PASOS = 300;
/** Sesiones que se conservan completas. Cada una puede tener muchos hijos. */
const MAX_SESIONES = 200;

interface Revision {
  id: string;
  tipo: string;
  nombre: string;
  ruta: string;
  nota: string;
  creado: string;
  estado: "pendiente" | "revisada" | "ajustada";
}

function leer(): Revision[] {
  try {
    const data = JSON.parse(readFileSync(ARCHIVO, "utf8"));
    return Array.isArray(data) ? data : [];
  } catch {
    return [];
  }
}

function guardar(items: Revision[]) {
  mkdirSync(dirname(ARCHIVO), { recursive: true });
  writeFileSync(ARCHIVO, JSON.stringify(items, null, 2) + "\n", "utf8");
}

function pendientes(): Revision[] {
  return leer().filter((r) => r.estado === "pendiente");
}

// ------------------------------------------------------------------ tareas

function leerTareas(): Tarea[] {
  try {
    const data = JSON.parse(readFileSync(TAREAS, "utf8"));
    if (!Array.isArray(data)) return [];
    return (data as Tarea[]).map((t) => ({
      ...t,
      pasos: Array.isArray(t.pasos) ? t.pasos : [],
    }));
  } catch {
    return [];
  }
}

/** Guarda sin romper los árboles: conserva las últimas MAX_SESIONES completas
 *  (raíz + todos sus subtickets) en vez de cortar por cantidad de tickets. */
function podar(items: Tarea[]): Tarea[] {
  const roots = raicesDe(items);
  if (!roots.length) return items.slice(-MAX_SESIONES * 20);
  const conservar = new Set(roots.slice(-MAX_SESIONES).map((r) => r.id));
  return items.filter((t) => conservar.has(raizDe(items, t).id));
}

/** Guarda con write+rename: si el proceso muere a mitad, no deja el JSON roto. */
function guardarTareas(items: Tarea[]): void {
  mkdirSync(dirname(TAREAS), { recursive: true });
  const tmp = `${TAREAS}.${process.pid}.tmp`;
  const finales = podar(items).sort((a, b) => a.creado.localeCompare(b.creado));
  writeFileSync(tmp, `${JSON.stringify(finales, null, 2)}\n`, "utf8");
  renameSync(tmp, TAREAS);
}

/** Espera sincrónica corta (el lock se tiene por milisegundos). */
function dormir(ms: number): void {
  try {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
  } catch {
    const fin = Date.now() + ms;
    while (Date.now() < fin) {
      /* sin Atomics: espera activa muy corta */
    }
  }
}

/** Varios agentes pueden escribir `tareas.json` a la vez. El lock por carpeta
 *  evita que uno pise el último paso del otro en el read-modify-write. Los
 *  lectores no lo necesitan: `rename` es atómico. */
function conLock<T>(fn: () => T): T {
  const lock = join(DIR, "tareas.lock");
  mkdirSync(DIR, { recursive: true });
  const fin = Date.now() + 800;
  let tomado = false;
  while (Date.now() < fin) {
    try {
      mkdirSync(lock);
      tomado = true;
      break;
    } catch {
      try {
        // Lock huérfano de un proceso que murió: se libera a los 15 s.
        if (Date.now() - statSync(lock).mtimeMs > 15_000) rmdirSync(lock);
      } catch {
        /* otro proceso lo liberó: reintentar */
      }
      dormir(12);
    }
  }
  try {
    return fn();
  } finally {
    if (tomado) {
      try {
        rmdirSync(lock);
      } catch {
        /* ya no estaba */
      }
    }
  }
}

/** Texto plano de un resultado de herramienta, para el resumen del trace. */
function textoResultado(contenido: unknown): string {
  if (!Array.isArray(contenido)) return "";
  const partes: string[] = [];
  for (const bloque of contenido) {
    if (!bloque || typeof bloque !== "object") continue;
    const b = bloque as { type?: string; text?: string };
    if (b.type === "text" && b.text) partes.push(b.text);
  }
  return partes.join(" ").replace(/\s+/g, " ").trim();
}

const POLITICA_SOFTWARE = `Todo trabajo de software se hace así, siempre:
1. **Árbol de features primero.** Antes de tocar código, leé el árbol de features del repo (\`features/\`, \`docs/features/\` o equivalente). Ahí está qué necesita la app, feature por feature, con su criterio de aceptación.
2. **Un verificador determinista por feature.** Cada feature tiene un script que la chequea sin criterio humano (en \`scripts/verify/\` o equivalente). Si agregás una feature, agregás su verificador; sin verificador, la feature no está terminada.
3. **Verificá antes de publicar.** Antes de decir que un cambio quedó listo, corré el verificador de las features que tocaste y el global (\`make check\` / \`scripts/verify/run-all.sh\`). Si falla, no está listo. Si no podés correrlo, decilo.
4. **Rastro de decisiones.** Las decisiones de arquitectura van a \`DECISIONS.md\` con qué se eligió, por qué y qué se descartó. No reescribas la historia: agregá una entrada.
5. **Pensá en agentes.** Estructura, nombres y docs tienen que dejar que otro agente entienda y extienda la app sin contexto previo. Menos código, más claro.
6. **Eficiencia primero: presupuesto adaptativo (colibrí).** Antes de escribir, estimá el costo en CPU, memoria, red y batería, y elegí la opción más barata que cumpla. Lo que consuma recursos (video, imágenes, animación, polling, IA local, build) detecta el hardware y el contexto, arranca con un presupuesto conservador, se degrada sola cuando el equipo no da y deja un override explícito al usuario. Cargá al acercarse, reusá antes que recrear, medí antes de suponer. Aprovechar el hardware que hay sin trabarlo es parte del trabajo, no una optimización para después.`;

const POLITICA_REVISION = `Cuando crees una **skill**, un **agente**, o cualquier artefacto que el usuario deba aprobar:
1. **Instalala de inmediato** (symlink/registro en el lugar que corresponda).
2. **Pedí revisión humana** con \`pedir_revision_humana\`, indicando tipo, nombre, ruta y una nota de qué mirar.
3. **Avisá al usuario** en la respuesta: qué creaste, dónde quedó y que está pendiente de su revisión.
Nunca des por buena una skill/agente nuevo sin que haya pasado el check humano. Si el usuario ya lo revisó, resolvelo con \`revisiones_pendientes\`.`;

const POLITICA_TRAZABILIDAD = `Trazabilidad (rig): cada agente vivo tiene UN ticket raíz abierto (su sesión) y cada pedido del usuario abre un subticket propio; no mezcles pedidos distintos en el mismo trace.
- Cuando delegues en un subagente o dividas el trabajo, creá un subticket con \`tarea\` (acción \`subtarea\`) antes de empezar.
- Dejá notas de decisiones con \`tarea\` (acción \`nota\`).
- El mismo ticket no lo trabaja otro agente: si un ticket es de otra sesión, solo lo leés y creás uno nuevo para lo tuyo.
- Todo el árbol queda en \`~/.local/share/pi/trazas/<raíz>.md\` (Markdown legible) y en \`/tareas\` / \`/traza\`.`;

function formatoLista(items: Revision[]): string {
  if (items.length === 0) return "No hay revisiones pendientes.";
  return items
    .map((r, i) => `${i + 1}. [${r.tipo}] ${r.nombre}\n   ruta: ${r.ruta}\n   nota: ${r.nota}\n   creado: ${r.creado}`)
    .join("\n\n");
}

/** Nombre del agente en este proceso: el mismo que usan la voz y el color. */
function tmuxOut(args: string[]): string {
  try {
    return execFileSync("tmux", args, {
      encoding: "utf8",
      timeout: 1500,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

function nombreAgente(): string {
  const explicit =
    (corridaHeadless() ? process.env.PI_RIG_AGENTE?.trim() : "") ||
    process.env.PI_VOICE_AGENT?.trim();
  if (explicit) return explicit;
  const pane = process.env.TMUX_PANE?.trim();
  if (pane) {
    const n = tmuxOut(["display-message", "-p", "-t", pane, "#{@agent_name}"]);
    if (n) return n;
  }
  try {
    const base = basename(process.cwd());
    if (base) return base;
  } catch {
    /* sin cwd */
  }
  return "pi";
}

/** Un subagente corre `pi -p --no-session` en el mismo panel que el padre.
 *  No debe crear otra raíz ni tocar el panel: solo aporta su ticket hijo. */
function corridaHeadless(): boolean {
  const args = process.argv.slice(1);
  if (args.includes("-p") || args.includes("--print") || args.includes("--no-session")) {
    return true;
  }
  const i = args.indexOf("--mode");
  return i >= 0 && args[i + 1] === "json";
}

function cwdActual(): string {
  try {
    return process.cwd();
  } catch {
    return "";
  }
}

export default function rig(pi: ExtensionAPI) {
  // --------------------------------------------------------------- tareas
  /** Ticket activo: el subticket del pedido en curso. */
  let tarea: Tarea | undefined;
  /** Ticket raíz: la sesión/agente vivo. Uno por sesión. */
  let raiz: Tarea | undefined;
  /** En un subagente, ticket de la delegación que lo lanzó. */
  let padreExterno: string | undefined;
  let esSubagente = false;
  let agente = "pi";
  let sessionPath: string | undefined;
  let sessionId: string | undefined;
  let guardadoTimer: ReturnType<typeof setTimeout> | undefined;
  /** toolCallId del subagente -> ticket hijo que sigue su resultado. */
  const subagentes = new Map<string, string>();

  function actualizarSesion(ctx: unknown): void {
    const sm = (ctx as {
      sessionManager?: { getSessionFile?: () => unknown; getSessionId?: () => unknown };
    })?.sessionManager;
    try {
      const file = sm?.getSessionFile?.();
      sessionPath = typeof file === "string" && file ? file : undefined;
    } catch {
      sessionPath = undefined;
    }
    try {
      const id = sm?.getSessionId?.();
      sessionId = typeof id === "string" && id ? id : undefined;
    } catch {
      sessionId = undefined;
    }
  }

  /** Dueño del ticket. Un ticket solo se muta desde su sesión. */
  function duenoDe(t: Tarea): string {
    return String(t.dueno ?? t.sessionId ?? "");
  }

  function esMia(t: Tarea | undefined): boolean {
    if (!t) return false;
    const dueno = duenoDe(t);
    return !dueno || dueno === sessionId;
  }

  function guardarUna(t: Tarea): void {
    conLock(() => {
      const items = leerTareas().filter((x) => x.id !== t.id);
      items.push(t);
      guardarTareas(items);
    });
  }

  function guardarVarias(ts: Tarea[]): void {
    if (!ts.length) return;
    conLock(() => {
      const ids = new Set(ts.map((t) => t.id));
      const items = leerTareas().filter((x) => !ids.has(x.id));
      items.push(...ts);
      guardarTareas(items);
    });
  }

  /** Las trazas también viven en Markdown: fácil de abrir y de seguir. */
  function exportarTraza(): void {
    const root = raiz;
    if (!root) return;
    try {
      mkdirSync(TRAZAS, { recursive: true });
      const items = leerTareas();
      const actual = items.find((t) => t.id === root.id) ?? root;
      writeFileSync(join(TRAZAS, `${actual.id}.md`), markdownTraza(actual, items), "utf8");
      writeFileSync(join(TRAZAS, "index.md"), indiceMarkdown(items), "utf8");
    } catch {
      /* sin permiso o disco lleno: el JSON sigue siendo la fuente */
    }
  }

  /** Escribe solo la tarea actual y la raíz, sin pisar las demás. En un
   *  subagente, la raíz es del padre: no se toca ni se exporta desde acá. */
  function volcar(): void {
    if (guardadoTimer) {
      clearTimeout(guardadoTimer);
      guardadoTimer = undefined;
    }
    if (tarea) {
      if (tarea.pasos.length > MAX_PASOS) {
        tarea.pasos.splice(0, tarea.pasos.length - MAX_PASOS);
      }
      tarea.actualizado = new Date().toISOString();
      guardarUna(tarea);
    }
    if (raiz && raiz.id !== tarea?.id && !esSubagente) {
      raiz.actualizado = new Date().toISOString();
      guardarUna(raiz);
    }
    if (!esSubagente) exportarTraza();
  }

  function programarGuardado(): void {
    if (guardadoTimer) return;
    guardadoTimer = setTimeout(() => {
      guardadoTimer = undefined;
      volcar();
    }, 350);
    guardadoTimer.unref?.();
  }

  function emitir(): void {
    try {
      pi.events.emit("rig:tarea", {
        id: tarea?.id ?? "",
        titulo: tarea?.titulo ?? "",
        estado: tarea?.estado ?? "",
        session: sessionPath,
        raiz: raiz?.id ?? "",
        agente,
      });
    } catch {
      /* sin bus de eventos: el latido igual muestra el pedido de respaldo */
    }
  }

  interface CrearOpciones {
    titulo?: string;
    pedido?: string;
    padre?: string;
    tipo?: TipoTarea;
    agente?: string;
    pasos?: Paso[];
    estado?: EstadoTarea;
  }

  function crearTarea(texto: string, opciones: CrearOpciones = {}): Tarea {
    const ahora = new Date();
    const usados = new Set(leerTareas().map((t) => t.id));
    let id = idTarea(ahora.getTime());
    while (usados.has(id)) id = idTarea(ahora.getTime(), Math.random());
    return {
      id,
      titulo: opciones.titulo ?? tituloDePedido(texto),
      pedido: recortar(opciones.pedido ?? texto, 1200),
      creado: ahora.toISOString(),
      actualizado: ahora.toISOString(),
      estado: opciones.estado ?? "activa",
      session: sessionPath,
      sessionId,
      dueno: sessionId,
      agente: opciones.agente ?? agente,
      padre: opciones.padre,
      tipo: opciones.tipo ?? "pedido",
      pasos:
        opciones.pasos ?? [
          { t: ahora.toISOString(), tipo: "pedido", resumen: recortar(texto, 240) },
        ],
    };
  }

  /** Ticket raíz de ESTA sesión. Si la sesión se reanuda, se reabre el mismo
   *  (no se crea otro): un agente vivo = un ticket raíz. */
  function asegurarRaiz(): Tarea {
    const items = leerTareas();
    const existente = items.find(
      (t) =>
        esRaiz(t) &&
        ((sessionId && (t.sessionId === sessionId || t.dueno === sessionId)) ||
          (sessionPath && t.session === sessionPath)),
    );
    if (existente) {
      raiz = existente;
      raiz.estado = "activa";
      raiz.hasta = undefined;
      raiz.actualizado = new Date().toISOString();
      raiz.agente = raiz.agente || agente;
      raiz.dueno = raiz.dueno || sessionId;
      raiz.pasos.push({
        t: raiz.actualizado,
        tipo: "nota",
        resumen: "sesión reanudada",
      });
      guardarUna(raiz);
      return raiz;
    }
    const cwd = cwdActual();
    const r = crearTarea(`Sesión de ${agente}${cwd ? ` en ${cwd}` : ""}`, {
      titulo: `sesión ${agente}`,
      pedido: `Sesión de ${agente}${cwd ? ` en ${cwd}` : ""}`,
      tipo: "sesion",
      pasos: [
        {
          t: new Date().toISOString(),
          tipo: "nota",
          resumen: `sesión abierta${cwd ? ` en ${cwd}` : ""}`,
        },
      ],
    });
    raiz = r;
    guardarUna(r);
    return r;
  }

  // Solo continuaciones explícitas y cortas ("dale", "seguí", "y ..."). Ojo:
  // "ahora ..." o "revisá ..." suelen ser un pedido nuevo, con su propio id.
  const CONTINUACION =
    /^(continuemos|continuá|continua|continúa|seguí|segui|sigue|dale|ok\b|okey|perfecto|bien\b|y\b|pero\b)/i;

  /** Un mensaje corto justo después de cerrar una tarea es la misma tarea.
   *  Si no, es un pedido nuevo y merece su propio ticket. */
  function esContinuacion(texto: string, t: Tarea): boolean {
    if (t.estado !== "lista") return false;
    const hace = Date.now() - Date.parse(t.actualizado);
    if (!(hace >= 0 && hace < 20 * 60 * 1000)) return false;
    const n = texto.split(/\s+/).filter(Boolean).length;
    return n <= 10 && CONTINUACION.test(texto);
  }

  pi.on("session_start", async (_event, ctx) => {
    actualizarSesion(ctx);
    agente = nombreAgente();
    tarea = undefined;
    raiz = undefined;
    padreExterno = undefined;
    subagentes.clear();

    const envPadre = process.env.PI_RIG_PADRE?.trim();
    esSubagente = Boolean(envPadre) && corridaHeadless();
    if (esSubagente) {
      // Subagente: no crea otra raíz ni toca el panel del padre. Su trabajo
      // cuelga del ticket de delegación que ya creó el padre.
      padreExterno = envPadre;
      const items = leerTareas();
      const padre = items.find((t) => t.id === envPadre);
      raiz = padre ? raizDe(items, padre) : undefined;
      emitir();
      return;
    }

    raiz = asegurarRaiz();
    const items = leerTareas();
    // Al reanudar, el header vuelve a mostrar el último subticket de ESTA
    // conversación. Si no hay, queda la raíz hasta el primer pedido.
    const propias = deLaSesion(items, sessionId, sessionPath).filter(
      (t) => t.id !== raiz!.id,
    );
    tarea = propias.length ? propias[propias.length - 1] : undefined;
    emitir();
  });

  pi.on("input", (event, ctx) => {
    if (event.source === "extension") return;
    const texto = String(event.text ?? "").trim();
    if (!texto) return;
    actualizarSesion(ctx);
    if (!raiz && !esSubagente) raiz = asegurarRaiz();
    const resumen = recortar(texto, 240);
    const ultimo = tarea?.pasos[tarea.pasos.length - 1];
    const repetido =
      ultimo?.tipo === "pedido" &&
      ultimo.resumen === resumen &&
      Date.now() - Date.parse(ultimo.t) < 2000;

    if (esSubagente) {
      // El subagente deja su propio ticket hijo, colgando de la delegación.
      // Si ya existe, el encargo se suma al mismo trace.
      if (!tarea) {
        tarea = crearTarea(texto, {
          padre: padreExterno,
          tipo: "subtarea",
          agente,
        });
      } else if (!repetido) {
        tarea.estado = "activa";
        tarea.hasta = undefined;
        tarea.actualizado = new Date().toISOString();
        tarea.pasos.push({ t: tarea.actualizado, tipo: "pedido", resumen });
      }
    } else if (
      tarea &&
      tarea.id !== raiz?.id &&
      esMia(tarea) &&
      (tarea.estado === "activa" || esContinuacion(texto, tarea))
    ) {
      // Mismo trabajo: el pedido extra queda como paso del mismo trace.
      tarea.estado = "activa";
      tarea.hasta = undefined;
      tarea.actualizado = new Date().toISOString();
      if (!repetido) {
        tarea.pasos.push({ t: tarea.actualizado, tipo: "pedido", resumen });
      }
    } else if (!repetido) {
      // Pedido nuevo = subticket nuevo bajo la sesión, con su propio trace.
      tarea = crearTarea(texto, { padre: raiz?.id, tipo: "pedido" });
    }
    volcar();
    emitir();
  });

  function ticketPorId(id: string): Tarea | undefined {
    if (tarea?.id === id) return tarea;
    if (raiz?.id === id) return raiz;
    return leerTareas().find((t) => t.id === id);
  }

  function registrarPaso(ticketId: string, event: {
    toolName: string;
    toolCallId: string;
    input: unknown;
  }): void {
    const t = ticketPorId(ticketId);
    if (!t || t.pasos.some((p) => p.id === event.toolCallId)) return;
    t.pasos.push({
      t: new Date().toISOString(),
      tipo: "tool",
      nombre: event.toolName,
      id: event.toolCallId,
      resumen: resumenEntrada(event.toolName, event.input),
    });
    if (t.pasos.length > MAX_PASOS) {
      t.pasos.splice(0, t.pasos.length - MAX_PASOS);
    }
    if (t.id !== tarea?.id && t.id !== raiz?.id) guardarUna(t);
    else programarGuardado();
  }

  /** Texto que describe una delegación: quién(es) y qué se les pidió. */
  function delegacion(event: { input: unknown }): { titulo: string; agente: string } {
    const input = (event.input ?? {}) as {
      agent?: string;
      task?: string;
      tasks?: Array<{ agent?: string; task?: string }>;
      chain?: Array<{ agent?: string; task?: string }>;
    };
    const tareaDe = (x: { agent?: string; task?: string } | undefined) =>
      String(x?.task ?? "").replace(/\s+/g, " ").trim();
    if (Array.isArray(input.tasks) && input.tasks.length) {
      const agentes = input.tasks.map((x) => String(x?.agent ?? "?")).join(", ");
      return {
        titulo: recortar(`subagentes ${agentes}: ${tareaDe(input.tasks[0])}`, 80),
        agente: agentes,
      };
    }
    if (Array.isArray(input.chain) && input.chain.length) {
      const agentes = input.chain.map((x) => String(x?.agent ?? "?")).join(" → ");
      return {
        titulo: recortar(`cadena ${agentes}: ${tareaDe(input.chain[0])}`, 80),
        agente: agentes,
      };
    }
    const agenteSub = String(input.agent ?? "").trim() || "subagente";
    return {
      titulo: recortar(`${agenteSub}: ${tareaDe(input)}`, 80),
      agente: agenteSub,
    };
  }

  /** Crea el subticket de una llamada `subagent`. El agente que delega sigue
   *  con su ticket; la delegación queda como hijo en el árbol. El proceso hijo
   *  hereda PI_RIG_PADRE/PI_RIG_AGENTE y cuelga su propio trabajo de este
   *  ticket en vez de inventar otra sesión. */
  function subticketDeSubagente(event: {
    toolCallId: string;
    input: unknown;
  }): Tarea | undefined {
    if (!tarea) return undefined;
    const d = delegacion(event);
    const hijo = crearTarea(d.titulo, {
      titulo: d.titulo,
      pedido: d.titulo,
      padre: tarea.id,
      tipo: "subtarea",
      agente: d.agente,
    });
    guardarUna(hijo);
    process.env.PI_RIG_PADRE = hijo.id;
    process.env.PI_RIG_AGENTE = d.agente;
    return hijo;
  }

  pi.on("tool_call", (event) => {
    if (!raiz) return;
    // Herramientas ejecutadas dentro de un subagente (si el harness las
    // propaga): se anotan en el ticket hijo que les corresponde.
    if (event.parentToolCallId) {
      const hijo = subagentes.get(event.parentToolCallId);
      if (hijo) registrarPaso(hijo, event);
      return;
    }
    if (!tarea) return;
    if (event.toolName === "subagent") {
      const hijo = subticketDeSubagente(event);
      if (hijo) {
        subagentes.set(event.toolCallId, hijo.id);
        tarea.pasos.push({
          t: new Date().toISOString(),
          tipo: "nota",
          resumen: `subticket ${hijo.id} · ${hijo.titulo}`,
        });
      }
    }
    registrarPaso(tarea.id, event);
  });

  pi.on("tool_result", (event) => {
    if (event.parentToolCallId) {
      const hijo = subagentes.get(event.parentToolCallId);
      if (hijo) {
        const t = ticketPorId(hijo);
        if (t) {
          t.pasos.push({
            t: new Date().toISOString(),
            tipo: "nota",
            resumen: `resultado: ${recortar(textoResultado(event.content), 220)}`,
          });
          guardarUna(t);
        }
      }
      return;
    }
    const hijoId = subagentes.get(event.toolCallId);
    if (hijoId) {
      // La delegación terminó: el subticket queda listo, con su resultado.
      const t = ticketPorId(hijoId);
      if (t) {
        t.estado = "lista";
        t.hasta = new Date().toISOString();
        t.pasos.push({
          t: t.hasta,
          tipo: "nota",
          resumen: `delegación terminada: ${recortar(textoResultado(event.content), 220)}`,
        });
        guardarUna(t);
      }
    }
    if (!tarea) return;
    const paso = tarea.pasos.find((p) => p.id === event.toolCallId);
    if (paso) {
      paso.ok = !event.isError;
      paso.ms = Math.max(0, Date.now() - Date.parse(paso.t));
      paso.resultado = recortar(textoResultado(event.content), 140);
    }
    programarGuardado();
  });

  pi.on("message_end", (event) => {
    if (!tarea) return;
    const mensaje = event.message as { role?: string; content?: unknown };
    if (mensaje?.role !== "assistant" || !Array.isArray(mensaje.content)) return;
    const pensado = mensaje.content
      .filter(
        (b): b is { type?: string; thinking?: string } => !!b && typeof b === "object",
      )
      .filter((b) => b.type === "thinking")
      .map((b) => String(b.thinking ?? ""))
      .join(" ")
      .replace(/\s+/g, " ")
      .trim();
    if (!pensado) return;
    const resumen = recortar(pensado, 300);
    const ultimo = tarea.pasos[tarea.pasos.length - 1];
    if (ultimo?.tipo === "pensamiento" && ultimo.resumen === resumen) return;
    tarea.pasos.push({ t: new Date().toISOString(), tipo: "pensamiento", resumen });
    programarGuardado();
  });

  pi.on("agent_settled", async () => {
    if (tarea && tarea.estado === "activa") {
      tarea.estado = "lista";
      tarea.hasta = new Date().toISOString();
    }
    volcar();
    emitir();
  });

  pi.on("session_shutdown", async () => {
    const ahora = new Date().toISOString();
    if (esSubagente) {
      // El subagente cierra su propio ticket, nunca la raíz ni la delegación
      // del padre (el padre marca el resultado de la delegación).
      if (tarea && tarea.estado === "activa") {
        tarea.estado = "cerrada";
        tarea.hasta = ahora;
      }
      volcar();
      return;
    }
    // La sesión se cierra: el ticket raíz deja de estar abierto y los pedidos
    // que quedaron activos se cierran con ella (sin borrar nada del trace).
    if (tarea && tarea.estado === "activa") {
      tarea.estado = "cerrada";
      tarea.hasta = ahora;
    }
    if (raiz) {
      raiz.estado = "cerrada";
      raiz.hasta = ahora;
      raiz.pasos.push({
        t: ahora,
        tipo: "nota",
        resumen: "sesión cerrada",
      });
    }
    volcar();
    emitir();
  });

  // ---------------------------------------------------------------- tools
  pi.registerTool({
    name: "pedir_revision_humana",
    label: "Pedir revisión humana",
    description:
      "Registra algo (skill, agente, artefacto) como pendiente de revisión humana. " +
      "Usalo SIEMPRE que crees una skill o un agente: primero instalalo, después " +
      "llamá esta tool, y avisá al usuario en la respuesta.",
    promptSnippet: "Anotar algo pendiente de revisión humana",
    promptGuidelines: [
      "Cada vez que crees una skill o un agente, instalalo de inmediato y llamá a " +
        "`pedir_revision_humana` con tipo, nombre, ruta y una nota de qué mirar. " +
        "Después avisá al usuario que quedó pendiente de su revisión.",
    ],
    parameters: Type.Object({
      tipo: Type.String({ description: "Qué es: skill, agente, extension, app, doc..." }),
      nombre: Type.String({ description: "Nombre del artefacto" }),
      ruta: Type.String({ description: "Ruta donde quedó instalado" }),
      nota: Type.Optional(Type.String({ description: "Qué debería mirar el usuario" })),
    }),
    async execute(_toolCallId, params) {
      const items = leer();
      const id = `rev-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
      const item: Revision = {
        id,
        tipo: String(params.tipo ?? "artefacto"),
        nombre: String(params.nombre ?? ""),
        ruta: String(params.ruta ?? ""),
        nota: String(params.nota ?? ""),
        creado: new Date().toISOString(),
        estado: "pendiente",
      };
      items.push(item);
      guardar(items);
      return {
        content: [
          {
            type: "text",
            text: `Anotado para revisión humana: [${item.tipo}] ${item.nombre} (${item.ruta}). Pendientes: ${pendientes().length}.`,
          },
        ],
        details: { id, pendientes: pendientes().length },
      };
    },
  });

  pi.registerTool({
    name: "revisiones_pendientes",
    label: "Listar o resolver revisiones pendientes",
    description:
      "Lista las revisiones humanas pendientes y permite resolverlas (marcar como " +
      "revisada o ajustada) cuando el usuario ya las miró.",
    promptSnippet: "Ver o resolver la cola de revisión humana",
    parameters: Type.Object({
      accion: Type.Optional(
        Type.Union([Type.Literal("listar"), Type.Literal("resolver")], {
          description: "listar (default) o resolver",
        }),
      ),
      id: Type.Optional(Type.String({ description: "id a resolver" })),
      estado: Type.Optional(
        Type.Union([Type.Literal("revisada"), Type.Literal("ajustada")], {
          description: "estado final al resolver",
        }),
      ),
    }),
    async execute(_toolCallId, params) {
      if (params.accion === "resolver" && params.id) {
        const items = leer();
        const item = items.find((r) => r.id === params.id);
        if (!item) {
          return { content: [{ type: "text", text: `No encontré la revisión ${params.id}.` }], details: undefined };
        }
        item.estado = params.estado === "ajustada" ? "ajustada" : "revisada";
        guardar(items);
        return {
          content: [{ type: "text", text: `Revisión ${params.id} marcada como ${item.estado}.` }],
          details: undefined,
        };
      }
      return { content: [{ type: "text", text: formatoLista(pendientes()) }], details: undefined };
    },
  });

  pi.registerTool({
    name: "tarea",
    label: "Ver o ajustar el ticket actual",
    description:
      "Cada sesión es un ticket raíz (el agente vivo) y cada pedido del usuario es " +
      "un subticket con su trace. Usá esta tool para renombrar el ticket actual, " +
      "dejar una nota de decisión, crear un subticket para una delegación o " +
      "cerrarlo. Con acción 'ver' devuelve el trace del ticket y sus hijos.",
    promptSnippet: "Ver o ajustar el ticket actual y crear subtickets",
    promptGuidelines: [
      "Los tickets se capturan solos: no hace falta crearlos. Si el título " +
        "automático no describe el trabajo, renombralo con `tarea` (acción renombrar).",
      "Antes de cerrar, dejá una nota con `tarea` (acción nota) y revisá el " +
        "árbol con `tareas`.",
      "Cuando delegues o dividas trabajo, creá un subticket con `tarea` " +
        "(acción subtarea) y después usá ese id en la delegación.",
    ],
    parameters: Type.Object({
      accion: Type.Optional(
        Type.Union(
          [
            Type.Literal("ver"),
            Type.Literal("renombrar"),
            Type.Literal("nota"),
            Type.Literal("subtarea"),
            Type.Literal("cerrar"),
          ],
          { description: "ver | renombrar | nota | subtarea | cerrar (default ver)" },
        ),
      ),
      titulo: Type.Optional(
        Type.String({ description: "Título nuevo o del subticket." }),
      ),
      nota: Type.Optional(
        Type.String({ description: "Nota, decisión o encargo del subticket." }),
      ),
      agente: Type.Optional(
        Type.String({ description: "Agente que va a trabajar el subticket (opcional)." }),
      ),
    }),
    async execute(_toolCallId, params) {
      if (!tarea) {
        return {
          content: [{ type: "text", text: "No hay ticket activo en esta sesión." }],
          details: undefined,
        };
      }
      if (!esMia(tarea)) {
        return {
          content: [
            {
              type: "text",
              text: `El ticket ${tarea.id} pertenece a otro agente (${duenoDe(tarea)}); en esta sesión solo lo puedo leer.`,
            },
          ],
          details: undefined,
        };
      }
      const accion = String(params.accion ?? "ver");
      if (accion === "renombrar") {
        const titulo = recortar(String(params.titulo ?? "").trim(), 80);
        if (!titulo) {
          return {
            content: [{ type: "text", text: "Falta el título nuevo." }],
            details: undefined,
          };
        }
        tarea.titulo = titulo;
        volcar();
        emitir();
        return {
          content: [{ type: "text", text: `Ticket ${tarea.id} renombrado: "${titulo}".` }],
          details: { id: tarea.id, titulo },
        };
      }
      if (accion === "nota") {
        const nota = recortar(String(params.nota ?? "").trim(), 400);
        if (!nota) {
          return {
            content: [{ type: "text", text: "Falta la nota." }],
            details: undefined,
          };
        }
        tarea.pasos.push({ t: new Date().toISOString(), tipo: "nota", resumen: nota });
        volcar();
        return {
          content: [{ type: "text", text: `Nota agregada al trace de ${tarea.id}.` }],
          details: { id: tarea.id },
        };
      }
      if (accion === "subtarea") {
        const titulo = recortar(String(params.titulo ?? "").trim(), 80);
        if (!titulo) {
          return {
            content: [{ type: "text", text: "Falta el título del subticket." }],
            details: undefined,
          };
        }
        const encargo = String(params.nota ?? "").trim();
        const subAgente = String(params.agente ?? "").trim() || agente;
        const hijo = crearTarea(encargo || titulo, {
          titulo,
          pedido: encargo || titulo,
          padre: tarea.id,
          tipo: "subtarea",
          agente: subAgente,
          pasos: [
            {
              t: new Date().toISOString(),
              tipo: "pedido",
              resumen: recortar(encargo || titulo, 240),
            },
          ],
        });
        tarea.pasos.push({
          t: new Date().toISOString(),
          tipo: "nota",
          resumen: `subticket ${hijo.id} · ${titulo}${subAgente ? ` · ${subAgente}` : ""}`,
        });
        guardarVarias([tarea, hijo]);
        exportarTraza();
        return {
          content: [
            {
              type: "text",
              text: `Subticket ${hijo.id} creado bajo ${tarea.id}: "${titulo}"${subAgente ? ` (agente ${subAgente})` : ""}.`,
            },
          ],
          details: { id: hijo.id, padre: tarea.id },
        };
      }
      if (accion === "cerrar") {
        tarea.estado = "cerrada";
        tarea.hasta = new Date().toISOString();
        volcar();
        emitir();
        return {
          content: [{ type: "text", text: `Ticket ${tarea.id} cerrado.` }],
          details: { id: tarea.id },
        };
      }
      const items = leerTareas();
      return {
        content: [{ type: "text", text: textoTraza(tarea, items, { maxPasos: 80 }) }],
        details: { id: tarea.id, raiz: raiz?.id },
      };
    },
  });

  pi.registerTool({
    name: "tareas",
    label: "Listar el árbol de tickets o ver un trace",
    description:
      "Lista el árbol de tickets (sesión → pedidos → delegaciones) o devuelve el " +
      "trace completo de un ticket con sus hijos. Sirve para retomar el hilo " +
      "exacto de un trabajo anterior y para ver qué agente hizo cada cosa.",
    promptSnippet: "Listar el árbol de tickets o ver el trace de uno",
    parameters: Type.Object({
      accion: Type.Optional(
        Type.Union([Type.Literal("listar"), Type.Literal("ver")], {
          description: "listar (default) o ver",
        }),
      ),
      id: Type.Optional(
        Type.String({ description: "Id del ticket a ver (ej. T-3F7K2A)." }),
      ),
      limite: Type.Optional(
        Type.Number({ description: "Cuántas sesiones listar (default 12)" }),
      ),
    }),
    async execute(_toolCallId, params) {
      const items = leerTareas();
      if (params.accion === "ver") {
        const id = String(params.id ?? "").trim().toUpperCase();
        const encontrada = id
          ? items.find((t) => t.id === id) ?? (tarea?.id === id ? tarea : undefined)
          : tarea;
        if (!encontrada) {
          return {
            content: [
              { type: "text", text: id ? `No encontré el ticket ${id}.` : "No hay ticket activo." },
            ],
            details: undefined,
          };
        }
        const lineas: string[] = [];
        const root = raizDe(items, encontrada);
        if (esRaiz(encontrada)) {
          lineas.push("ÁRBOL", ...lineasArbol(items, encontrada.id), "");
        } else {
          lineas.push(`raíz: ${root.id} · ${root.titulo}`, "");
        }
        lineas.push(textoTraza(encontrada, items, { maxPasos: 120 }));
        return {
          content: [{ type: "text", text: lineas.join("\n") }],
          details: { id: encontrada.id, raiz: root.id },
        };
      }

      const limite = Math.max(1, Math.min(40, Number(params.limite ?? 12) || 12));
      const propias = deLaSesion(items, sessionId, sessionPath);
      const miRaiz = raiz ?? (propias.length ? raizDe(items, propias[0]!) : undefined);
      const roots = raicesDe(items);
      const otras = roots.filter((r) => r.id !== miRaiz?.id).slice(-limite).reverse();
      const lineas: string[] = [];
      if (miRaiz) {
        lineas.push(`SESIÓN ACTUAL · ${miRaiz.id}`, ...lineasArbol(items, miRaiz.id));
      }
      if (otras.length) {
        lineas.push("", "OTRAS SESIONES");
        for (const r of otras) {
          const n = 1 + descendientesDe(items, r.id).length;
          lineas.push(
            `${r.id} ${r.estado} · ${r.titulo} · ${r.agente || "sin agente"} · ${n} ticket(s)`,
          );
        }
      }
      if (!lineas.length) lineas.push("Todavía no hay tickets registrados.");
      return { content: [{ type: "text", text: lineas.join("\n") }], details: undefined };
    },
  });

  // -------------------------------------------------------------- command
  pi.registerCommand("revisiones", {
    description: "Lista las revisiones humanas pendientes",
    handler: async (_args, ctx) => {
      ctx.ui.notify(formatoLista(pendientes()), pendientes().length ? "warning" : "info");
    },
  });

  pi.registerCommand("tareas", {
    description: "Árbol de tickets de esta sesión y de las anteriores",
    handler: async (_args, ctx) => {
      const items = leerTareas();
      const propias = deLaSesion(items, sessionId, sessionPath);
      const miRaiz = raiz ?? (propias.length ? raizDe(items, propias[0]!) : undefined);
      const lineas: string[] = [];
      if (miRaiz) lineas.push(...lineasArbol(items, miRaiz.id));
      const otras = raicesDe(items)
        .filter((r) => r.id !== miRaiz?.id)
        .slice(-10)
        .reverse();
      if (otras.length) {
        lineas.push("", "Otras sesiones:");
        for (const r of otras) {
          lineas.push(`■ ${r.id} · ${r.titulo} · ${r.agente || "sin agente"}`);
        }
      }
      if (!lineas.length) {
        ctx.ui.notify("Todavía no hay tickets registrados.", "info");
        return;
      }
      ctx.ui.notify(lineas.slice(0, 32).join("\n"), "info");
    },
  });

  pi.registerCommand("tarea", {
    description: "Muestra el trace de un ticket (/tarea T-XXXXXX; sin id cierra el panel)",
    handler: async (args, ctx) => {
      const pedido = String(args ?? "").trim();
      if (!pedido) {
        ctx.ui.setWidget("rig-tarea", undefined);
        return;
      }
      const id = pedido.toUpperCase().startsWith("T-")
        ? pedido.toUpperCase()
        : `T-${pedido.toUpperCase()}`;
      const items = leerTareas();
      const encontrada =
        items.find((t) => t.id === id) ??
        (tarea && (tarea.id === id || tarea.id.endsWith(id.slice(2))) ? tarea : undefined);
      if (!encontrada) {
        ctx.ui.notify(`No encontré el ticket ${id}. Probá con /tareas.`, "warning");
        return;
      }
      const lineas = textoTraza(encontrada, items, { maxPasos: 60 })
        .split("\n")
        .map((l) => recortar(l, 180))
        .slice(0, 40);
      ctx.ui.setWidget("rig-tarea", lineas);
      ctx.ui.notify(`Trace de ${encontrada.id} en el panel. /tarea sin id lo cierra.`, "info");
    },
  });

  pi.registerCommand("traza", {
    description: "Árbol completo de esta sesión + ruta del Markdown (/traza [T-XXXXXX])",
    handler: async (args, ctx) => {
      const pedido = String(args ?? "").trim();
      if (!pedido) {
        ctx.ui.setWidget("rig-traza", undefined);
        return;
      }
      const items = leerTareas();
      const id = pedido.toUpperCase().startsWith("T-")
        ? pedido.toUpperCase()
        : `T-${pedido.toUpperCase()}`;
      const encontrada =
        items.find((t) => t.id === id) ??
        items.find((t) => t.id.endsWith(id.slice(2)));
      const root = encontrada
        ? esRaiz(encontrada)
          ? encontrada
          : raizDe(items, encontrada)
        : raiz;
      if (!root) {
        ctx.ui.notify("No hay una sesión con traza todavía.", "info");
        return;
      }
      const lineas = lineasArbol(items, root.id).slice(0, 40).map((l) => recortar(l, 180));
      ctx.ui.setWidget("rig-traza", lineas);
      ctx.ui.notify(
        `Traza de ${root.id} en el panel (${lineas.length} línea(s)). Markdown: ${join(TRAZAS, `${root.id}.md`)}. /traza sin id lo cierra.`,
        "info",
      );
    },
  });

  pi.registerCommand("trazas", {
    description: "Índice de trazas de todos los agentes",
    handler: async (_args, ctx) => {
      if (!existsSync(join(TRAZAS, "index.md"))) {
        ctx.ui.notify("Todavía no hay trazas. Pedile algo a un agente y volvé.", "info");
        return;
      }
      ctx.ui.notify(`Trazas: ${join(TRAZAS, "index.md")}`, "info");
    },
  });

  // ----------------------------------------------------- recordatorio
  pi.on("session_start", async (_event, ctx) => {
    const n = pendientes().length;
    if (n > 0) {
      ctx.ui.notify(
        `Tenés ${n} revisión(es) humana(s) pendiente(s). Mirá con /revisiones antes de olvidarte.`,
        "warning",
      );
    }
  });

  // --------------------------------------------------------- prompt fijo
  pi.on("before_agent_start", (event) => {
    event.systemPromptOptions.sections.metodo_software = POLITICA_SOFTWARE;
    event.systemPromptOptions.sections.revision_humana = POLITICA_REVISION;
    event.systemPromptOptions.sections.trazabilidad = POLITICA_TRAZABILIDAD;
  });
}
