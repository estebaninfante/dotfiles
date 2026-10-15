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
 *  2. Latido (`PI_LATIDO_MS`, default 60000): cada ~1 minuto de trabajo le pide
 *     al modelo, en una línea, que diga qué está haciendo y si tiene alguna duda;
 *     si la tiene, que la pregunte con `avisar` (voz) o `preguntar_al_usuario`
 *     (voz + espera). Así deja de rumiar en silencio.
 *
 * El bus vive en ~/developing/voz-agentes/agente (configurable con PI_AGENTE_BIN).
 * El nombre del agente (que decide su voz) sale de PI_VOICE_AGENT (default "pi").
 *
 * Config:
 *   PI_AGENTE_BIN     ruta al bus (default ~/developing/voz-agentes/agente)
 *   PI_VOICE_AGENT    nombre del agente / perfil de voz (default "pi")
 *   PI_LATIDO=0       apaga el latido
 *   PI_LATIDO_MS      intervalo del latido (default 60000)
 */

import { spawn } from "node:child_process";
import { appendFileSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const HOME = process.env.HOME ?? "";
const AGENTE_BIN = process.env.PI_AGENTE_BIN ?? `${HOME}/developing/voz-agentes/agente`;
const AGENT_NAME = process.env.PI_VOICE_AGENT ?? "pi";

const LATIDO_ENABLED = process.env.PI_LATIDO !== "0";
const LATIDO_MS = Number(process.env.PI_LATIDO_MS ?? "60000") || 60000;

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
  let thinkingBuf = "";
  let textBuf = "";
  let uiCtx: { ui?: { setStatus?: (k: string, v?: string) => void; setWidget?: (k: string, v?: string[]) => void } } | undefined;

  /** Un trozo del pensamiento del modelo (o de su respuesta, si no piensa). */
  function snippet(): string {
    const buf = (thinkingBuf || textBuf).replace(/\s+/g, " ").trim();
    if (!buf) return "…";
    const max = 280;
    if (buf.length <= max) return buf;
    const start = Math.floor(Math.random() * (buf.length - max));
    return `…${buf.slice(start, start + max)}…`;
  }

  /** Muestra/actualiza el widget con el pensamiento en vivo y el tiempo. */
  function updateLatido(): void {
    if (!working) return;
    const ui = uiCtx?.ui;
    if (!ui) return;
    const secs = Math.round((Date.now() - workStart) / 1000);
    try {
      ui.setStatus?.("voz-latido", `⏱ ${secs}s`);
      ui.setWidget?.("voz-latido", [`⏱ Pensando hace ${secs}s`, snippet()]);
    } catch {
      /* sin UI (modo rpc/print): no importa */
    }
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

  pi.on("before_agent_start", (_event, ctx) => {
    working = true;
    workStart = Date.now();
    outstanding = false;
    thinkingBuf = "";
    textBuf = "";
    uiCtx = ctx;
    updateLatido();
  });

  // Razonamiento/respuesta en vivo: acumulo los deltas para mostrar un trozo.
  pi.on("message_update", (event, ctx) => {
    uiCtx = ctx;
    const e = (event as { assistantMessageEvent?: { type?: string; delta?: string } }).assistantMessageEvent;
    if (!e || typeof e.delta !== "string") return;
    if (e.type === "thinking_delta") thinkingBuf += e.delta;
    else if (e.type === "text_delta") textBuf += e.delta;
  });

  pi.on("turn_end", async (_event, ctx) => {
    uiCtx = ctx;
    outstanding = false;
    updateLatido();
  });

  pi.on("agent_settled", async (_event, ctx) => {
    working = false;
    outstanding = false;
    uiCtx = ctx;
    clearLatido();
  });

  // El "punto de control" ya NO es un mensaje al modelo (se perdía y lo
  // interrumpía). Ahora es un widget de la UI que muestra hace cuánto trabaja
  // y recuerda cómo preguntar, sin tocar la conversación.
  let timer: ReturnType<typeof setInterval> | undefined;
  if (LATIDO_ENABLED) {
    timer = setInterval(updateLatido, 5000);
    if (typeof timer.unref === "function") timer.unref();
  }

  pi.on("session_shutdown", async () => {
    if (timer) clearInterval(timer);
    clearLatido();
  });
}
