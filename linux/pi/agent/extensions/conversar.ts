/**
 * conversar — convierte la voz de una sola dirección en una conversación.
 *
 * `tts-summary.ts` ya hace que el agente HABLE (`avisar`). Esta extensión agrega
 * las dos piezas que faltan:
 *
 *  1. Tool `preguntar_al_usuario`: el agente hace una pregunta en voz alta y
 *     ESPERA tu respuesta hablada. Mientras espera no gasta tokens adivinando.
 *     Usa el bus `agente` (preguntar → esperar), que a su vez reutiliza el
 *     daemon de voz (`voice send --agent <nombre>`) y serializa varios agentes.
 *
 *  2. Subtítulos de trabajo: mientras el modelo piensa, un widget de la UI
 *     muestra hace cuánto trabaja, cuál fue el último pedido del usuario y el
 *     pensamiento en vivo en trozos legibles. Así el usuario puede seguirle el
 *     paso sin depender de la voz.
 *
 * El bus vive en ~/developing/voz-agentes/agente (configurable con PI_AGENTE_BIN).
 * El nombre del agente (que decide su voz) sale de PI_VOICE_AGENT (default "pi").
 *
 * El widget de latido muestra, mientras el modelo trabaja:
 *   - Hace cuánto piensa (segundos).
 *   - El último pedido del usuario (para no perder de vista el objetivo).
 *   - Los subtítulos del pensamiento en vivo: una ventana de pocas palabras,
 *     siempre entera (nunca corta a mitad de palabra), que avanza palabra por
 *     palabra al ritmo de lectura y resalta la palabra actual. Si el modelo
 *     piensa mucho más rápido de lo que se puede leer, se descartan las
 *     palabras más viejas para no quedar atrasado.
 *
 * Config:
 *   PI_AGENTE_BIN        ruta al bus (default ~/developing/voz-agentes/agente)
 *   PI_VOICE_AGENT       nombre del agente / perfil de voz (default "pi")
 *   PI_LATIDO=0          apaga el latido
 *   PI_LATIDO_WORDS      palabras visibles en la ventana (default 14)
 *   PI_LATIDO_WORD_MS    ritmo de lectura, ms por palabra (default 360)
 *   PI_LATIDO_BACKLOG    máximo de palabras en espera antes de descartar (default 80)
 *   PI_LATIDO_PROMPT_CHARS  largo máximo del pedido mostrado (default 96)
 */

import { spawn } from "node:child_process";
import { appendFileSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const HOME = process.env.HOME ?? "";
const AGENTE_BIN = process.env.PI_AGENTE_BIN ?? `${HOME}/developing/voz-agentes/agente`;
const AGENT_NAME = process.env.PI_VOICE_AGENT ?? "pi";

const LATIDO_ENABLED = process.env.PI_LATIDO !== "0";

// Subtítulos del pensamiento: ventana corta, palabras enteras, ritmo legible.
const VISIBLE_WORDS = Math.max(4, Number(process.env.PI_LATIDO_WORDS ?? "14") || 14);
const WORD_MS = Math.max(120, Number(process.env.PI_LATIDO_WORD_MS ?? "360") || 360);
const MAX_BACKLOG = Math.max(VISIBLE_WORDS, Number(process.env.PI_LATIDO_BACKLOG ?? "80") || 80);
const PROMPT_MAX = Math.max(20, Number(process.env.PI_LATIDO_PROMPT_CHARS ?? "96") || 96);
const PACER_TICK_MS = 120;

/** Registro para poder verificar el latido sin adivinar (PI_LATIDO_DEBUG=1). */
function beatLog(msg: string): void {
  if (process.env.PI_LATIDO_DEBUG !== "1") return;
  try {
    appendFileSync(process.env.PI_LATIDO_LOG ?? "/tmp/pi-latido.log", `${new Date().toISOString()} ${msg}\n`);
  } catch {
    /* sin permiso de escritura: no importa */
  }
}

interface ExecResult {
  code: number;
  stdout: string;
  stderr: string;
}

/** Corre el bus y captura salida; respeta el aborto del turno. */
function execCapture(
  args: string[],
  timeoutMs: number,
  signal?: AbortSignal,
): Promise<ExecResult> {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(AGENTE_BIN, args, { stdio: ["ignore", "pipe", "pipe"] });
    } catch (err) {
      resolve({ code: 127, stdout: "", stderr: String(err) });
      return;
    }
    let stdout = "";
    let stderr = "";
    let done = false;
    const finish = (code: number) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      signal?.removeEventListener("abort", onAbort);
      resolve({ code, stdout, stderr });
    };
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      finish(124);
    }, Math.max(1000, timeoutMs));
    const onAbort = () => {
      child.kill("SIGTERM");
      finish(130);
    };
    signal?.addEventListener("abort", onAbort, { once: true });
    child.stdout?.on("data", (d) => (stdout += String(d)));
    child.stderr?.on("data", (d) => (stderr += String(d)));
    child.on("error", (err) => {
      stderr += String(err);
      finish(127);
    });
    child.on("close", (code) => finish(code ?? 0));
  });
}

const PREGUNTAR_PARAMS = Type.Object({
  pregunta: Type.String({
    description:
      "La pregunta para el usuario, en español natural y sencillo, una sola " +
      "frase, sin tecnicismos. Se leerá en voz alta.",
  }),
  espera_segundos: Type.Optional(
    Type.Number({
      description:
        "Cuánto esperar la respuesta hablada antes de seguir por tu cuenta " +
        "(default 300). Si no responde, seguí con tu mejor criterio y decile " +
        "después qué asumiste.",
    }),
  ),
});

export default function (pi: ExtensionAPI) {
  let lastBeat = 0;
  let outstanding = false;
  let working = false;
  let workStart = 0;
  let hasThinking = false;
  let uiCtx: {
    ui?: {
      setStatus?: (k: string, v?: string) => void;
      setWidget?: (k: string, v?: string[]) => void;
      theme?: { style?: (text: string, options: Record<string, unknown>) => string };
    };
  } | undefined;

  // Subtítulos del pensamiento: cola de palabras que se libera al ritmo de
  // lectura para poder seguirle el paso (karaoke), sin cortar palabras.
  let wordCarry = ""; // resto de la última palabra todavía incompleta
  let wordQueue: string[] = []; // palabras completas pendientes de mostrar
  let visibleWords: string[] = []; // ventana móvil que se está leyendo
  let dropped = false; // se descartaron palabras por ir muy detrás del modelo
  let lastRelease = 0;
  let lastRender = 0;
  let lastPrompt = ""; // último pedido del usuario, para recordar el objetivo

  /** Normaliza espacios sin romper palabras. */
  function cleanText(s: unknown): string {
    return String(s ?? "").replace(/\s+/g, " ").trim();
  }

  /** Recorta por caracteres respetando el límite de palabra. */
  function truncateWords(text: string, max: number): string {
    const t = cleanText(text);
    if (t.length <= max) return t;
    const cut = t.slice(0, max);
    const sp = cut.lastIndexOf(" ");
    return `${(sp > max * 0.5 ? cut.slice(0, sp) : cut).trimEnd()}…`;
  }

  /** Último pedido del usuario leído de la sesión (para restaurar al reanudar). */
  function lastUserPrompt(
    ctx: { sessionManager?: { getEntries?: () => unknown[] } } | undefined,
  ): string {
    try {
      const entries = ctx?.sessionManager?.getEntries?.() ?? [];
      for (let i = entries.length - 1; i >= 0; i--) {
        const entry = entries[i] as {
          type?: string;
          message?: { role?: string; content?: unknown };
        };
        if (entry?.type !== "message" || entry.message?.role !== "user") continue;
        const content = entry.message.content;
        if (typeof content === "string") {
          const t = cleanText(content);
          if (t) return t;
        } else if (Array.isArray(content)) {
          const t = cleanText(
            content
              .filter((b): b is { type?: string; text?: string } => !!b && typeof b === "object")
              .filter((b) => b.type === "text")
              .map((b) => b.text)
              .join(" "),
          );
          if (t) return t;
        }
      }
    } catch {
      /* sin sesión: no importa */
    }
    return "";
  }

  /** Encola palabras completas; guarda el resto para el próximo fragmento. */
  function feedWords(chunk: string): void {
    wordCarry += chunk;
    const m = /^(.*\s)(\S*)$/s.exec(wordCarry);
    if (!m) return;
    wordCarry = m[2];
    for (const w of m[1].split(/\s+/)) if (w) wordQueue.push(w);
    if (wordQueue.length > MAX_BACKLOG) {
      wordQueue.splice(0, wordQueue.length - MAX_BACKLOG);
      dropped = true;
    }
  }

  /** Libera una palabra al ritmo de lectura y la suma a la ventana visible. */
  function releaseWord(): void {
    if (!wordQueue.length) return;
    visibleWords.push(wordQueue.shift() as string);
    if (visibleWords.length > VISIBLE_WORDS) {
      visibleWords.splice(0, visibleWords.length - VISIBLE_WORDS);
    }
    lastRelease = Date.now();
    updateLatido();
  }

  /** Resalta una palabra con el tema activo (inverso como respaldo). */
  function highlight(word: string): string {
    try {
      const styled = uiCtx?.ui?.theme?.style?.(word, {
        fg: "accent",
        bg: "selectedBg",
        bold: true,
        underline: true,
      });
      if (styled) return styled;
    } catch {
      /* tema sin ese color: cae al respaldo */
    }
    return `\x1b[4;7m${word}\x1b[0m`;
  }

  /** El trozo visible: solo palabras enteras; la última va resaltada. */
  function snippet(): string {
    if (!visibleWords.length) return "…";
    const head = visibleWords.slice(0, -1).join(" ");
    const tail = visibleWords[visibleWords.length - 1];
    return `${dropped ? "… " : ""}${head ? `${head} ` : ""}${highlight(tail)}`;
  }

  /** Muestra/actualiza el widget con el pedido, el tiempo y el pensamiento vivo. */
  function updateLatido(): void {
    if (!working) return;
    const ui = uiCtx?.ui;
    if (!ui) return;
    lastRender = Date.now();
    const secs = Math.round((Date.now() - workStart) / 1000);
    const goal = lastPrompt ? `🎯 ${truncateWords(lastPrompt, PROMPT_MAX)}` : "🎯 (sin pedido aún)";
    try {
      ui.setStatus?.("voz-latido", `⏱ ${secs}s`);
      ui.setWidget?.("voz-latido", [`⏱ Pensando hace ${secs}s`, goal, snippet()]);
    } catch {
      /* sin UI (modo rpc/print): no importa */
    }
  }

  /** Ritmo: libera una palabra cuando toca y mantiene el reloj al día. */
  function tickLatido(): void {
    const now = Date.now();
    if (!working) return;
    if (wordQueue.length && now - lastRelease >= WORD_MS) releaseWord();
    else if (now - lastRender >= 1000) updateLatido();
  }

  function clearLatido(): void {
    try {
      uiCtx?.ui?.setStatus?.("voz-latido", undefined);
      uiCtx?.ui?.setWidget?.("voz-latido", undefined);
    } catch {
      /* noop */
    }
  }

  pi.registerTool({
    name: "preguntar_al_usuario",
    label: "Preguntar al usuario (voz, espera respuesta)",
    description:
      "Hace una pregunta al usuario en voz alta y ESPERA su respuesta hablada. " +
      "Devolvé como resultado lo que el usuario respondió y continuá con eso. " +
      "Usala en vez de asumir cuando el pedido es ambiguo o cuando vas a gastar " +
      "pasos probando algo que el usuario puede responder en una frase.",
    promptSnippet:
      "Preguntar al usuario por voz y esperar su respuesta (en vez de asumir)",
    promptGuidelines: [
      "Si el pedido es ambiguo, o si estás por asumir algo que el usuario puede " +
        "responder en una frase, usá `preguntar_al_usuario` ANTES de gastar pasos " +
        "adivinando o probando. El usuario es tu mejor fuente de verdad.",
      "No uses `preguntar_al_usuario` para cosas que ya podés resolver leyendo el " +
        "repositorio o la documentación.",
    ],
    parameters: PREGUNTAR_PARAMS,
    async execute(_toolCallId, params, signal) {
      const pregunta = String(params.pregunta ?? "").trim();
      if (!pregunta) {
        return { content: [{ type: "text", text: "Falta la pregunta." }], details: undefined };
      }
      const espera = Math.max(10, Number(params.espera_segundos ?? 300) || 300);
      await execCapture(["preguntar", AGENT_NAME, pregunta], 15000, signal);
      const answer = await execCapture(
        ["esperar", AGENT_NAME, "--timeout", String(espera)],
        espera * 1000 + 5000,
        signal,
      );
      const text = answer.stdout.trim();
      if (answer.code === 0 && text) {
        return {
          content: [
            { type: "text", text: `El usuario respondió por voz: "${text}". Continuá con eso.` },
          ],
          details: undefined,
        };
      }
      if (signal?.aborted) {
        return {
          content: [{ type: "text", text: "El usuario interrumpió antes de responder." }],
          details: undefined,
        };
      }
      return {
        content: [
          {
            type: "text",
            text:
              `El usuario no respondió en ${espera}s. Seguí con tu mejor criterio ` +
              "y, cuando puedas, decile con `avisar` qué asumiste.",
          },
        ],
        details: undefined,
      };
    },
  });

  // Recuerda el último pedido del usuario para mostrarlo mientras trabaja.
  pi.on("input", (event) => {
    const e = event as { source?: string; text?: string };
    if (e?.source === "extension") return;
    const t = cleanText(e?.text);
    if (t) lastPrompt = t;
  });

  pi.on("session_start", async (_event, ctx) => {
    uiCtx = ctx;
    const restored = lastUserPrompt(ctx as never);
    if (restored) lastPrompt = restored;
  });

  pi.on("before_agent_start", (_event, ctx) => {
    working = true;
    workStart = Date.now();
    outstanding = false;
    hasThinking = false;
    wordCarry = "";
    wordQueue = [];
    visibleWords = [];
    dropped = false;
    lastRelease = Date.now();
    uiCtx = ctx;
    updateLatido();
  });

  // Razonamiento/respuesta en vivo: encolo palabras enteras para los subtítulos.
  // Si el modelo no razona, uso su respuesta como respaldo.
  pi.on("message_update", (event, ctx) => {
    uiCtx = ctx;
    const e = (event as { assistantMessageEvent?: { type?: string; delta?: string } }).assistantMessageEvent;
    if (!e || typeof e.delta !== "string") return;
    if (e.type === "thinking_delta") {
      hasThinking = true;
      feedWords(e.delta);
    } else if (e.type === "text_delta" && !hasThinking) {
      feedWords(e.delta);
    }
  });

  pi.on("turn_end", async (_event, ctx) => {
    uiCtx = ctx;
    outstanding = false;
    updateLatido();
  });

  pi.on("agent_settled", async (_event, ctx) => {
    working = false;
    outstanding = false;
    wordQueue = [];
    uiCtx = ctx;
    clearLatido();
  });

  // El "punto de control" ya NO es un mensaje al modelo (se perdía y lo
  // interrumpía). Ahora es un widget de la UI que muestra hace cuánto trabaja
  // y recuerda cómo preguntar, sin tocar la conversación.
  let timer: ReturnType<typeof setInterval> | undefined;
  if (LATIDO_ENABLED) {
    timer = setInterval(tickLatido, PACER_TICK_MS);
    if (typeof timer.unref === "function") timer.unref();
  }

  pi.on("session_shutdown", async () => {
    if (timer) clearInterval(timer);
    clearLatido();
  });
}
