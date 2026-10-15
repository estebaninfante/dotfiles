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
 *   - Hace cuánto piensa: por turno y acumulado de la sesión, en horas,
 *     minutos y segundos según corresponda.
 *   - El último pedido del usuario (para no perder de vista el objetivo);
 *     queda a la vista también cuando el modelo termina.
 *   - Los subtítulos del pensamiento: se toma una oración corta y se deja fija
 *     en pantalla; se ilumina palabra por palabra al ritmo de lectura. El
 *     párrafo no se mueve ni cambia: recién cuando se termina de iluminar
 *     entra el siguiente. Si el modelo piensa mucho más rápido de lo que se
 *     puede leer, se descartan las oraciones más viejas para no quedar atrasado.
 *
 * Config:
 *   PI_AGENTE_BIN        ruta al bus (default ~/developing/voz-agentes/agente)
 *   PI_VOICE_AGENT       nombre del agente / perfil de voz (default "pi")
 *   PI_LATIDO=0          apaga el latido
 *   PI_LATIDO_PARAGRAPH_WORDS  palabras tope por oración (default 24)
 *   PI_LATIDO_WORD_MS    ritmo de lectura, ms por palabra (default 360)
 *   PI_LATIDO_BACKLOG    máximo de palabras en espera antes de descartar (default 120)
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

// Subtítulos del pensamiento: una oración fija que se ilumina palabra por
// palabra al ritmo de lectura; no es una ventana que se desplaza.
const PARAGRAPH_WORDS = Math.max(6, Number(process.env.PI_LATIDO_PARAGRAPH_WORDS ?? "24") || 24);
const WORD_MS = Math.max(120, Number(process.env.PI_LATIDO_WORD_MS ?? "360") || 360);
const MAX_BACKLOG = Math.max(PARAGRAPH_WORDS, Number(process.env.PI_LATIDO_BACKLOG ?? "120") || 120);
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
      theme?: {
        style?: (text: string, options: Record<string, unknown>) => string;
        fg?: (token: string, text: string) => string;
      };
    };
  } | undefined;

  // Subtítulos del pensamiento: se acumula el texto que llega, se corta por
  // oración y se muestra una oración fija; la iluminación avanza palabra por
  // palabra al ritmo de lectura. No hay ventana que se desplaza.
  let sentenceBuf = ""; // texto de la oración que todavía no cerró
  let paragraphs: string[][] = []; // oraciones listas, ya en palabras
  let current: string[] | null = null; // oración fija que se está iluminando
  let currentIndex = 0; // palabra iluminada dentro de `current`
  let dropped = false; // se descartaron oraciones por ir muy detrás del modelo
  let lastRelease = 0;
  let lastRender = 0;
  let lastRenderedKey = "";
  let lastPrompt = ""; // último pedido del usuario, para recordar el objetivo
  let sessionThinkingMs = 0; // acumulado de la sesión
  let lastTurnMs = 0; // duración del último turno

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

  /** Corta el texto en palabras enteras. */
  function words(text: string): string[] {
    return cleanText(text).split(/\s+/).filter(Boolean);
  }

  /** Encola una oración; si el atraso crece, descarta las más viejas. */
  function pushParagraph(text: string): void {
    const w = words(text);
    if (!w.length) return;
    paragraphs.push(w);
    let total = paragraphs.reduce((n, p) => n + p.length, 0);
    while (paragraphs.length > 1 && total > MAX_BACKLOG) {
      total -= paragraphs[0].length;
      paragraphs.shift();
      dropped = true;
    }
  }

  /** Acumula el pensamiento y cierra oraciones al ritmo en que aparecen. */
  function feedThinking(chunk: string): void {
    if (!chunk) return;
    sentenceBuf += chunk;
    for (;;) {
      const m = /^(.*?[.!?…\n])(\s+|$)/s.exec(sentenceBuf);
      if (!m) break;
      const sentence = m[1].replace(/\n/g, " ");
      sentenceBuf = sentenceBuf.slice(m[0].length);
      pushParagraph(sentence);
    }
    // sin puntuación durante demasiado tiempo: cortamos por cantidad de palabras
    const pending = words(sentenceBuf);
    if (pending.length >= PARAGRAPH_WORDS) {
      pushParagraph(pending.slice(0, PARAGRAPH_WORDS).join(" "));
      sentenceBuf = pending.slice(PARAGRAPH_WORDS).join(" ");
    }
  }

  /** Toma la próxima oración de la cola y la deja fija para iluminarla. */
  function startNextParagraph(): void {
    const next = paragraphs.shift();
    if (!next || !next.length) return;
    current = next;
    currentIndex = 0;
    lastRelease = Date.now();
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

  /** Apaga una palabra que aún no se leyó (queda visible pero tenue). */
  function muted(word: string): string {
    try {
      const styled = uiCtx?.ui?.theme?.fg?.("muted", word);
      if (styled) return styled;
    } catch {
      /* tema sin "muted": cae al respaldo */
    }
    return `\x1b[2m${word}\x1b[0m`;
  }

  /** La oración fija: lo ya leído, la palabra actual iluminada y lo que falta. */
  function snippet(): string {
    if (!current) return "…";
    const parts = current.map((w, i) => {
      if (i === currentIndex) return highlight(w);
      if (i < currentIndex) return w;
      return muted(w);
    });
    return `${dropped ? "… " : ""}${parts.join(" ")}`;
  }

  /** Duración en horas, minutos y segundos según corresponda. */
  function formatDuration(ms: number): string {
    const total = Math.max(0, Math.floor(ms / 1000));
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    if (h > 0) return `${h}h ${String(m).padStart(2, "0")}m ${String(s).padStart(2, "0")}s`;
    if (m > 0) return `${m}m ${String(s).padStart(2, "0")}s`;
    return `${s}s`;
  }

  /** Muestra/actualiza el widget con el pedido, los tiempos y el pensamiento. */
  function updateLatido(force = false): void {
    const ui = uiCtx?.ui;
    if (!ui) return;
    const now = Date.now();
    const turnMs = working ? now - workStart : lastTurnMs;
    const sessionMs = sessionThinkingMs + (working ? now - workStart : 0);
    const goal = lastPrompt ? `🎯 ${truncateWords(lastPrompt, PROMPT_MAX)}` : "🎯 (sin pedido aún)";
    const head = working
      ? `⏱ Pensando hace ${formatDuration(turnMs)} · Sesión ${formatDuration(sessionMs)}`
      : `✓ ${formatDuration(lastTurnMs)} · Sesión ${formatDuration(sessionThinkingMs)}`;
    const key = `${head}|${goal}|${currentIndex}|${current ? current.join(" ") : ""}|${dropped}`;
    if (!force && key === lastRenderedKey) return;
    lastRenderedKey = key;
    lastRender = now;
    const lines = [head, goal];
    if (working && current) lines.push(snippet());
    try {
      ui.setStatus?.("voz-latido", `⏱ ${formatDuration(turnMs)}`);
      ui.setWidget?.("voz-latido", lines);
    } catch {
      /* sin UI (modo rpc/print): no importa */
    }
  }

  /** Ritmo: ilumina la siguiente palabra cuando toca y mantiene el reloj. */
  function tickLatido(): void {
    if (!working) return;
    const now = Date.now();
    if (!current) startNextParagraph();
    while (current && now - lastRelease >= WORD_MS) {
      lastRelease += WORD_MS;
      currentIndex++;
      if (currentIndex >= current.length) {
        current = null;
        currentIndex = 0;
        if (paragraphs.length) startNextParagraph();
        break;
      }
    }
    updateLatido();
  }

  function clearLatido(): void {
    try {
      uiCtx?.ui?.setStatus?.("voz-latido", undefined);
      uiCtx?.ui?.setWidget?.("voz-latido", undefined);
    } catch {
      /* noop */
    }
  }

  /** Al terminar dejamos a la vista el pedido y los tiempos del turno. */
  function settleLatido(): void {
    current = null;
    currentIndex = 0;
    paragraphs = [];
    sentenceBuf = "";
    dropped = false;
    lastRenderedKey = "";
    try {
      uiCtx?.ui?.setStatus?.("voz-latido", undefined);
    } catch {
      /* noop */
    }
    updateLatido(true);
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
    // Si un turno anterior no llegó a asentarse, no perdemos su tiempo.
    if (working && workStart) sessionThinkingMs += Date.now() - workStart;
    working = true;
    workStart = Date.now();
    outstanding = false;
    hasThinking = false;
    sentenceBuf = "";
    paragraphs = [];
    current = null;
    currentIndex = 0;
    dropped = false;
    lastRelease = Date.now();
    lastRenderedKey = "";
    uiCtx = ctx;
    updateLatido(true);
  });

  // Razonamiento/respuesta en vivo: encolo palabras enteras para los subtítulos.
  // Si el modelo no razona, uso su respuesta como respaldo.
  pi.on("message_update", (event, ctx) => {
    uiCtx = ctx;
    const e = (event as { assistantMessageEvent?: { type?: string; delta?: string } }).assistantMessageEvent;
    if (!e || typeof e.delta !== "string") return;
    if (e.type === "thinking_delta") {
      hasThinking = true;
      feedThinking(e.delta);
    } else if (e.type === "text_delta" && !hasThinking) {
      feedThinking(e.delta);
    }
  });

  pi.on("turn_end", async (_event, ctx) => {
    uiCtx = ctx;
    outstanding = false;
    updateLatido();
  });

  pi.on("agent_settled", async (_event, ctx) => {
    if (working && workStart) {
      lastTurnMs = Date.now() - workStart;
      sessionThinkingMs += lastTurnMs;
    }
    working = false;
    outstanding = false;
    uiCtx = ctx;
    settleLatido();
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
