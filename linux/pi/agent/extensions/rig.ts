/**
 * rig — las reglas de trabajo del usuario, siempre presentes.
 *
 * Hace tres cosas:
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
 * 4. **Tareas con id y trace.** Cada pedido del usuario abre una tarea con id
 *    (`T-XXXXXX`), título corto y un trace de pasos: el pedido, cada llamada a
 *    herramienta con su resultado y un resumen de lo que pensó el modelo. No
 *    hay que crearlas a mano: se capturan solas. `/tareas` las lista y
 *    `/tarea <id>` muestra el trace en el panel. El agente también las ve con
 *    las tools `tarea` y `tareas`, y puede renombrar o anotar la actual.
 *
 * Los pendientes viven en `~/.local/share/pi/revisiones.json` y las tareas en
 * `~/.local/share/pi/tareas.json` (configurable con PI_RIG_DIR).
 */

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { Type } from "typebox";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  formatoDuracion,
  idTarea,
  recortar,
  resumenEntrada,
  tituloDePedido,
} from "./lib/pensamiento.ts";

const DIR = process.env.PI_RIG_DIR ?? join(homedir(), ".local", "share", "pi");
const ARCHIVO = join(DIR, "revisiones.json");
const TAREAS = join(DIR, "tareas.json");
const MAX_TAREAS = 200;
const MAX_PASOS = 200;

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

type EstadoTarea = "activa" | "lista" | "cerrada";
type TipoPaso = "pedido" | "tool" | "pensamiento" | "nota";

interface Paso {
  /** ISO de cuándo empezó el paso. */
  t: string;
  tipo: TipoPaso;
  resumen: string;
  nombre?: string;
  /** id de la llamada, para engancharle el resultado cuando vuelve. */
  id?: string;
  ok?: boolean;
  ms?: number;
  resultado?: string;
}

interface Tarea {
  id: string;
  titulo: string;
  pedido: string;
  creado: string;
  actualizado: string;
  hasta?: string;
  estado: EstadoTarea;
  session?: string;
  sessionId?: string;
  pasos: Paso[];
}

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

/** Guarda con write+rename: si el proceso muere a mitad, no deja el JSON roto. */
function guardarTareas(items: Tarea[]): void {
  mkdirSync(dirname(TAREAS), { recursive: true });
  const tmp = `${TAREAS}.${process.pid}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(items.slice(-MAX_TAREAS), null, 2)}\n`, "utf8");
  renameSync(tmp, TAREAS);
}

function hora(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? "--:--:--"
    : d.toLocaleTimeString("es-AR", { hour12: false });
}

function iconoPaso(p: Paso): string {
  if (p.tipo === "pedido") return "▶";
  if (p.tipo === "pensamiento") return "💭";
  if (p.tipo === "nota") return "·";
  return p.ok === false ? "✗" : p.ok ? "✓" : "…";
}

/** Trace legible de una tarea: lo que se pidió, qué herramientas se usaron,
 *  si salieron bien y qué se pensó. La conversación completa queda enlazada en
 *  `sesión:` para quien necesite el detalle exacto. */
function trazaTarea(t: Tarea, maxPasos = 120, conSesion = true): string {
  const dur = (t.hasta ? Date.parse(t.hasta) : Date.now()) - Date.parse(t.creado);
  const lineas = [
    `TAREA ${t.id} · ${t.titulo}`,
    `estado: ${t.estado} · ${formatoDuracion(dur)} · ${t.pasos.length} pasos`,
    `pedido: ${recortar(t.pedido, 400)}`,
  ];
  if (conSesion && t.session) lineas.push(`sesión: ${t.session}`);
  lineas.push("");
  for (const p of t.pasos.slice(-maxPasos)) {
    const nombre = p.nombre ? `${p.nombre} ` : "";
    const ms = p.ms != null ? ` (${p.ms}ms)` : "";
    lineas.push(`${hora(p.t)} ${iconoPaso(p)} ${nombre}${p.resumen}${ms}`);
    if (p.resultado) lineas.push(`        ↳ ${p.resultado}`);
  }
  return lineas.join("\n");
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
5. **Pensá en agentes.** Estructura, nombres y docs tienen que dejar que otro agente entienda y extienda la app sin contexto previo. Menos código, más claro.`;

const POLITICA_REVISION = `Cuando crees una **skill**, un **agente**, o cualquier artefacto que el usuario deba aprobar:
1. **Instalala de inmediato** (symlink/registro en el lugar que corresponda).
2. **Pedí revisión humana** con \`pedir_revision_humana\`, indicando tipo, nombre, ruta y una nota de qué mirar.
3. **Avisá al usuario** en la respuesta: qué creaste, dónde quedó y que está pendiente de su revisión.
Nunca des por buena una skill/agente nuevo sin que haya pasado el check humano. Si el usuario ya lo revisó, resolvelo con \`revisiones_pendientes\`.`;

function formatoLista(items: Revision[]): string {
  if (items.length === 0) return "No hay revisiones pendientes.";
  return items
    .map((r, i) => `${i + 1}. [${r.tipo}] ${r.nombre}\n   ruta: ${r.ruta}\n   nota: ${r.nota}\n   creado: ${r.creado}`)
    .join("\n\n");
}

export default function rig(pi: ExtensionAPI) {
  // --------------------------------------------------------------- tareas
  let tarea: Tarea | undefined;
  let sessionPath: string | undefined;
  let sessionId: string | undefined;
  let guardadoTimer: ReturnType<typeof setTimeout> | undefined;

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

  /** Escribe solo la tarea actual, sin pisar las demás del archivo. */
  function volcar(): void {
    if (guardadoTimer) {
      clearTimeout(guardadoTimer);
      guardadoTimer = undefined;
    }
    if (!tarea) return;
    tarea.actualizado = new Date().toISOString();
    const items = leerTareas().filter((t) => t.id !== tarea!.id);
    items.push(tarea);
    items.sort((a, b) => a.creado.localeCompare(b.creado));
    guardarTareas(items);
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
      });
    } catch {
      /* sin bus de eventos: el latido igual muestra el pedido de respaldo */
    }
  }

  function crearTarea(texto: string): Tarea {
    const ahora = new Date();
    const usados = new Set(leerTareas().map((t) => t.id));
    let id = idTarea(ahora.getTime());
    while (usados.has(id)) id = idTarea(ahora.getTime(), Math.random());
    return {
      id,
      titulo: tituloDePedido(texto),
      pedido: recortar(texto, 1200),
      creado: ahora.toISOString(),
      actualizado: ahora.toISOString(),
      estado: "activa",
      session: sessionPath,
      sessionId,
      pasos: [
        { t: ahora.toISOString(), tipo: "pedido", resumen: recortar(texto, 240) },
      ],
    };
  }

  // Solo continuaciones explícitas y cortas ("dale", "seguí", "y ..."). Ojo:
  // "ahora ..." o "revisá ..." suelen ser un pedido nuevo, con su propio id.
  const CONTINUACION =
    /^(continuemos|continuá|continua|continúa|seguí|segui|sigue|dale|ok\b|okey|perfecto|bien\b|y\b|pero\b)/i;

  /** Un mensaje corto justo después de cerrar una tarea es la misma tarea.
   *  Si no, es un pedido nuevo y merece su propio id. */
  function esContinuacion(texto: string, t: Tarea): boolean {
    if (t.estado !== "lista") return false;
    const hace = Date.now() - Date.parse(t.actualizado);
    if (!(hace >= 0 && hace < 20 * 60 * 1000)) return false;
    const n = texto.split(/\s+/).filter(Boolean).length;
    return n <= 10 && CONTINUACION.test(texto);
  }

  pi.on("session_start", async (_event, ctx) => {
    actualizarSesion(ctx);
    // Al reanudar, el encabezado vuelve a mostrar la última tarea de ESTA
    // conversación (o se limpia si es una sesión nueva).
    const previas = leerTareas().filter(
      (t) =>
        (sessionPath && t.session === sessionPath) ||
        (!sessionPath && sessionId && t.sessionId === sessionId),
    );
    tarea = previas.length ? previas[previas.length - 1] : undefined;
    emitir();
  });

  pi.on("input", (event, ctx) => {
    if (event.source === "extension") return;
    const texto = String(event.text ?? "").trim();
    if (!texto) return;
    actualizarSesion(ctx);
    const resumen = recortar(texto, 240);
    const ultimo = tarea?.pasos[tarea.pasos.length - 1];
    const repetido =
      ultimo?.tipo === "pedido" &&
      ultimo.resumen === resumen &&
      Date.now() - Date.parse(ultimo.t) < 2000;
    if (tarea && (tarea.estado === "activa" || esContinuacion(texto, tarea))) {
      // Mismo trabajo: el pedido extra queda como paso del mismo trace.
      tarea.estado = "activa";
      tarea.hasta = undefined;
      tarea.actualizado = new Date().toISOString();
      if (!repetido) {
        tarea.pasos.push({ t: tarea.actualizado, tipo: "pedido", resumen });
      }
    } else if (!repetido) {
      tarea = crearTarea(texto);
    }
    volcar();
    emitir();
  });

  pi.on("tool_call", (event) => {
    if (event.parentToolCallId || !tarea) return;
    const ahora = new Date().toISOString();
    tarea.pasos.push({
      t: ahora,
      tipo: "tool",
      nombre: event.toolName,
      id: event.toolCallId,
      resumen: resumenEntrada(event.toolName, event.input),
    });
    if (tarea.pasos.length > MAX_PASOS) {
      tarea.pasos.splice(0, tarea.pasos.length - MAX_PASOS);
    }
    programarGuardado();
  });

  pi.on("tool_result", (event) => {
    if (event.parentToolCallId || !tarea) return;
    const paso = tarea.pasos.find((p) => p.id === event.toolCallId);
    if (!paso) return;
    paso.ok = !event.isError;
    paso.ms = Math.max(0, Date.now() - Date.parse(paso.t));
    paso.resultado = recortar(textoResultado(event.content), 140);
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
    tarea.pasos.push({
      t: new Date().toISOString(),
      tipo: "pensamiento",
      resumen: recortar(pensado, 300),
    });
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
    volcar();
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
    label: "Ver o ajustar la tarea actual",
    description:
      "Cada pedido del usuario abre una tarea con id y trace automáticamente. " +
      "Usá esta tool para renombrarla si el título automático no describe el " +
      "trabajo, para dejar una nota en el trace o para cerrarla. Con acción " +
      "'ver' devuelve el trace de la tarea actual (pedido, herramientas y " +
      "pensamientos).",
    promptSnippet: "Ver o ajustar la tarea actual (el rig le pone id y trace solo)",
    promptGuidelines: [
      "Las tareas se capturan solas: no hace falta crearlas. Si el título " +
        "automático no describe el trabajo, renombrala con `tarea` (acción renombrar).",
      "Antes de cerrar, podés dejar una nota en el trace con `tarea` (acción nota) " +
        "y revisar tareas anteriores con `tareas`.",
    ],
    parameters: Type.Object({
      accion: Type.Union(
        [
          Type.Literal("ver"),
          Type.Literal("renombrar"),
          Type.Literal("nota"),
          Type.Literal("cerrar"),
        ],
        { description: "ver | renombrar | nota | cerrar (default ver)" },
      ),
      titulo: Type.Optional(
        Type.String({ description: "Título nuevo y corto (acción renombrar)." }),
      ),
      nota: Type.Optional(
        Type.String({ description: "Nota o decisión para el trace (acción nota)." }),
      ),
    }),
    async execute(_toolCallId, params) {
      if (!tarea) {
        return {
          content: [{ type: "text", text: "No hay tarea activa en esta sesión." }],
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
          content: [{ type: "text", text: `Tarea ${tarea.id} renombrada: "${titulo}".` }],
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
      if (accion === "cerrar") {
        tarea.estado = "cerrada";
        tarea.hasta = new Date().toISOString();
        volcar();
        emitir();
        return {
          content: [{ type: "text", text: `Tarea ${tarea.id} cerrada.` }],
          details: { id: tarea.id },
        };
      }
      return {
        content: [{ type: "text", text: trazaTarea(tarea, 60) }],
        details: { id: tarea.id },
      };
    },
  });

  pi.registerTool({
    name: "tareas",
    label: "Listar tareas o ver el trace de una",
    description:
      "Lista las tareas recientes con su id y título, o devuelve el trace " +
      "completo de una tarea (pedido, herramientas, resultados y pensamientos). " +
      "Sirve para retomar el hilo exacto de un trabajo anterior.",
    promptSnippet: "Listar tareas o ver el trace exacto de una",
    parameters: Type.Object({
      accion: Type.Optional(
        Type.Union([Type.Literal("listar"), Type.Literal("ver")], {
          description: "listar (default) o ver",
        }),
      ),
      id: Type.Optional(
        Type.String({ description: "Id de la tarea a ver (ej. T-3F7K2A)." }),
      ),
      limite: Type.Optional(
        Type.Number({ description: "Cuántas tareas listar (default 12)." }),
      ),
    }),
    async execute(_toolCallId, params) {
      if (params.accion === "ver") {
        const id = String(params.id ?? "").trim().toUpperCase();
        const encontrada = id
          ? leerTareas().find((t) => t.id === id) ?? (tarea?.id === id ? tarea : undefined)
          : tarea;
        if (!encontrada) {
          return {
            content: [
              { type: "text", text: id ? `No encontré la tarea ${id}.` : "No hay tarea activa." },
            ],
            details: undefined,
          };
        }
        return {
          content: [{ type: "text", text: trazaTarea(encontrada) }],
          details: { id: encontrada.id },
        };
      }
      const limite = Math.max(1, Math.min(40, Number(params.limite ?? 12) || 12));
      const items = leerTareas().slice(-limite).reverse();
      if (!items.length) {
        return {
          content: [{ type: "text", text: "Todavía no hay tareas registradas." }],
          details: undefined,
        };
      }
      const texto = items
        .map(
          (t) =>
            `${t.id} · ${t.estado} · ${t.titulo}${t.id === tarea?.id ? " (actual)" : ""}`,
        )
        .join("\n");
      return { content: [{ type: "text", text: texto }], details: undefined };
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
    description: "Lista las tareas recientes con su id",
    handler: async (_args, ctx) => {
      const items = leerTareas().slice(-12).reverse();
      if (!items.length) {
        ctx.ui.notify("Todavía no hay tareas registradas.", "info");
        return;
      }
      const actual = tarea?.id;
      const texto = items
        .map((t) => {
          const marca = t.estado === "activa" ? "▶" : t.estado === "lista" ? "✓" : "■";
          return `${marca} ${t.id} · ${t.titulo}${t.id === actual ? "  (actual)" : ""}`;
        })
        .join("\n");
      ctx.ui.notify(texto, "info");
    },
  });

  pi.registerCommand("tarea", {
    description: "Muestra el trace de una tarea (/tarea T-XXXXXX; sin id lo cierra)",
    handler: async (args, ctx) => {
      const pedido = String(args ?? "").trim();
      if (!pedido) {
        ctx.ui.setWidget("rig-tarea", undefined);
        return;
      }
      const id = pedido.toUpperCase().startsWith("T-")
        ? pedido.toUpperCase()
        : `T-${pedido.toUpperCase()}`;
      const encontrada =
        leerTareas().find((t) => t.id === id) ??
        (tarea && (tarea.id === id || tarea.id.endsWith(id.slice(2))) ? tarea : undefined);
      if (!encontrada) {
        ctx.ui.notify(`No encontré la tarea ${id}. Probá con /tareas.`, "warning");
        return;
      }
      const lineas = trazaTarea(encontrada, 40, false)
        .split("\n")
        .map((l) => recortar(l, 180))
        .slice(0, 36);
      ctx.ui.setWidget("rig-tarea", lineas);
      ctx.ui.notify(`Trace de ${encontrada.id} en el panel. /tarea sin id lo cierra.`, "info");
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
  });
}
