/**
 * tts-summary — el agente le HABLA al usuario al terminar (y cuando haga falta),
 * por el sistema de voz del equipo (`voice avisar`, que decide motor y volumen,
 * y registra el mensaje para poder repetirlo).
 * relativo al general configurable con `voice volume`).
 *
 * Motivo: el usuario se distrae y no se entera de que el agente terminó o de
 * que necesita algo. Una frase hablada lo trae de vuelta.
 *
 * Mecanismo principal: la tool `avisar`. El propio agente (que tiene todo el
 * contexto) escribe una sola frase en español llano —como quien le reporta un
 * avance a otra persona, o la pregunta que necesite— y la tool la entrega en
 * voz alta más una notificación de escritorio. La instrucción `promptGuidelines`
 * la hace obligatoria al terminar cada respuesta, y disponible en cualquier
 * momento.
 *
 * Red de seguridad: si el agente no llamó la tool en la corrida, al asentarse
 * Pi (`agent_settled`) un modelo reescribe su última respuesta en una frase
 * llana y la habla. Nunca deja mudo al usuario; nunca dice tecnicismos.
 *
 * Interruptor: el `tts.enabled` del sistema de voz (config.toml [tts] + override
 * en state.json). El widget de barra eztvn.pi-tts lo togglea con `voice tts`.
 *
 * Config:
 *   PI_TTS_VOICE_BIN   binario del sistema de voz (default: ~/.local/bin/voice)
 *   PI_TTS_DRY=1       no habla ni notifica; escribe en PI_TTS_DRY_FILE o /tmp
 */

import { execFileSync, spawn } from "node:child_process";
import { appendFileSync } from "node:fs";
import { basename } from "node:path";
import { uuidv7 } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

type Block = { type?: string; text?: string };
type Message = { content?: unknown };

type RunSummary = {
  texts: string[];
  errors: number;
};

const MAX_SUMMARY = 240;
const DEDUP_MS = 20000;
const HOME = process.env.HOME ?? "";

/** Nombre del agente que habla: así el subtítulo y la notificación dicen QUIÉN
 *  es (su color sale del nombre), no el harness. Prioridad: PI_VOICE_AGENT >
 *  nombre del panel tmux (@agent_name) > carpeta del proyecto > "pi". */
function resolveAgentName(): string {
  const explicit = process.env.PI_VOICE_AGENT?.trim();
  if (explicit) return explicit;
  const pane = process.env.TMUX_PANE?.trim();
  if (pane) {
    try {
      const name = execFileSync(
        "tmux",
        ["display-message", "-p", "-t", pane, "#{@agent_name}"],
        { encoding: "utf8", timeout: 1500, stdio: ["ignore", "pipe", "ignore"] },
      ).trim();
      if (name) return name;
    } catch {
      /* sin tmux o panel sin nombre: probamos la carpeta */
    }
  }
  try {
    const cwd = process.cwd();
    if (cwd && cwd !== HOME && !cwd.startsWith("/tmp") && !cwd.startsWith(`${HOME}/.`)) {
      const base = basename(cwd);
      if (base) return base;
    }
  } catch {
    /* sin cwd: no importa */
  }
  return "pi";
}

let agentNameCache: string | undefined;

/** Lazy: no toca tmux al cargar la extensión, recién cuando hace falta. */
function agentName(): string {
  return (agentNameCache ??= resolveAgentName());
}

/* Voz del jefe: una sola frase, resultados y no métodos. */
const SYSTEM_PROMPT = [
  "Recibes el reporte técnico de un agente que acaba de trabajar.",
  "Devuelve SOLO una frase, en español natural y sencillo, como quien le",
  "reporta un avance a otra persona: qué se hizo y si quedó listo.",
  "Prohibido: nombres de herramientas o funciones, comandos, rutas o nombres de",
  "archivos, siglas y tecnicismos. Habla de resultados, no de cómo se hizo.",
  "Sin listas, sin markdown, sin comillas. Si algo falló, dilo llanamente.",
  "No uses apelativos ni digas 'jefe'. No empieces con 'El agente' ni 'Yo':",
  "habla directo. Máximo 160 caracteres.",
].join(" ");

const AVISAR_PARAMS = Type.Object({
  mensaje: Type.String({
    description:
      "Una sola frase en español natural y sencillo, como le reportarías un " +
      "avance a otra persona (o le harías una pregunta). Sin tecnicismos, sin " +
      "rutas, sin nombres de herramientas o funciones, sin apelativos.",
  }),
});

function blocks(content: unknown): Block[] {
  return Array.isArray(content)
    ? content.filter((part): part is Block => Boolean(part) && typeof part === "object")
    : [];
}

/* Deja el texto apto para oír: fuera bloques de código, markdown, viñetas y
   links; colapsa espacios y recorta. `limit <= 0` = sin tope: lo usan los
   avisos escritos por el agente (ya vienen cortos y no deben cortarse a mitad
   de oración). El tope queda para el resumen automático de respaldo. */
function clean(line: string, limit = MAX_SUMMARY): string {
  const first = line
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/[\[\]()*_>#]/g, "")
    .replace(/[\r\n]+/g, " ")
    .replace(/^["'«“”\s]+|["'»“”\s]+$/g, "")
    .replace(/\s+/g, " ")
    .trim();
  if (limit > 0 && first.length > limit) {
    return `${first.slice(0, limit).trimEnd()}…`;
  }
  return first;
}

/* Recorte de respaldo, sólo si el modelo no está disponible. */
function condense(text: string): string {
  const flat = text
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/^\s{0,3}#{1,6}\s*/gm, "")
    .replace(/^\s*[-*+]\s+/gm, "")
    .replace(/[*_>#]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  if (!flat) return "";
  const sentences = flat.split(/(?<=[.!?…])\s+/);
  let out = "";
  for (const sentence of sentences) {
    if (out && out.length + sentence.length > MAX_SUMMARY) break;
    out = out ? `${out} ${sentence}` : sentence;
    if (out.length >= MAX_SUMMARY) break;
  }
  if (!out) out = flat;
  return out.length > MAX_SUMMARY ? `${out.slice(0, MAX_SUMMARY).trimEnd()}…` : out;
}

/* La extensión es solo un CLIENTE del sistema de voz (`voice`): el CLI decide
   si hablar, con qué voz y cómo registrarlo. Aquí no se relee la config ni se
   duplica el interruptor, así Pi deja de ser el dueño de la voz. El mismo
   `voice avisar` lo pueden usar opencode, la barra o cualquier otro proceso. */
function voiceAvisar(line: string): void {
  const bin = process.env.PI_TTS_VOICE_BIN ?? `${HOME}/.local/bin/voice`;
  try {
    const child = spawn(bin, ["avisar", "--source", agentName(), "--", line], {
      detached: true,
      stdio: "ignore",
    });
    child.unref();
  } catch {
    /* sin sistema de voz disponible: no rompe el turno */
  }
}

let lastDelivered = "";
let lastDeliveredAt = 0;

/* Dedup: evita repetir la misma frase en pocos segundos (el agente puede
   llamar a `avisar` a mitad y al final). */
function deliver(text: string, limit = MAX_SUMMARY): void {
  const line = clean(text, limit);
  if (!line) return;
  const now = Date.now();
  if (line === lastDelivered && now - lastDeliveredAt < DEDUP_MS) return;
  lastDelivered = line;
  lastDeliveredAt = now;
  if (process.env.PI_TTS_DRY === "1") {
    appendFileSync(process.env.PI_TTS_DRY_FILE ?? "/tmp/pi-tts-summary.txt", `${line}\n`);
    return;
  }
  voiceAvisar(line);
}

export default function (pi: ExtensionAPI) {
  let run: RunSummary = { texts: [], errors: 0 };
  let announced = false;

  pi.registerTool({
    name: "avisar",
    label: "Avisar por voz",
    description:
      "Avisa al usuario lo que debe saber (el sistema de voz lo habla o lo deja en su buzón). Llámala SIEMPRE al " +
      "terminar tu respuesta, y también en cualquier momento del trabajo si " +
      "surge algo que valga la pena avisar o preguntar, con una sola frase " +
      "breve en español natural y respetuoso, como quien le reporta un avance a " +
      "otra persona: qué hiciste y si quedó listo, o la pregunta que necesites " +
      "hacerle. Sin tecnicismos, sin rutas, sin nombres de herramientas o " +
      "funciones. No uses apelativos ni lo llames 'jefe'. Sirve para llamar su " +
      "atención: puede estar distraído y no mirar la pantalla.",
    promptSnippet: "Avisar al usuario (voz o buzón; obligatoria al terminar; disponible en cualquier momento)",
    promptGuidelines: [
      "SIEMPRE, al terminar cada respuesta, llama a `avisar` con una sola frase " +
        "breve, en español natural y respetuoso (como quien le reporta un avance " +
        "a otra persona): qué pasó o qué necesitas preguntarle. Nunca incluyas " +
        "tecnicismos, rutas ni nombres de herramientas; se dirá en voz alta o se " +
        "dejará en su buzón.",
      "También puedes usar `avisar` en cualquier momento, no sólo al final, si " +
        "aparece algo que convenga que el usuario sepa o tenga que decidir.",
      "No uses apelativos ni la palabra 'jefe': habla directo.",
    ],
    parameters: AVISAR_PARAMS,
    async execute(_toolCallId, params) {
      announced = true;
      // Sin tope: el aviso lo escribe el agente y ya viene en una frase breve;
      // recortarlo partia la oración a mitad.
      deliver(String(params.mensaje ?? ""), 0);
      return {
        content: [{ type: "text", text: "Avisado al usuario." }],
        details: undefined,
      };
    },
  });

  pi.on("before_agent_start", () => {
    announced = false;
  });

  pi.on("turn_end", async (event, ctx) => {
    const message = (event as { message?: Message }).message;
    for (const block of blocks(message?.content)) {
      if (block.type === "text" && typeof block.text === "string") {
        run.texts.push(block.text);
      }
    }
    const results = (event as { toolResults?: { isError?: boolean }[] }).toolResults ?? [];
    run.errors += results.filter((result) => result?.isError).length;

    /* Respaldo si el evento no trae contenido: leer la ultima respuesta. */
    if (!run.texts.length && ctx?.sessionManager) {
      for (const entry of ctx.sessionManager.getEntries().slice(-8)) {
        if (entry.type === "message" && entry.message.role === "assistant") {
          for (const block of blocks(entry.message.content)) {
            if (block.type === "text" && typeof block.text === "string") run.texts.push(block.text);
          }
        }
      }
    }
  });

  pi.on("agent_settled", async (_event, ctx) => {
    const snapshot = run;
    run = { texts: [], errors: 0 };
    const agentAlreadySpoke = announced;
    announced = false;
    if (agentAlreadySpoke) return;

    const raw = (snapshot.texts[snapshot.texts.length - 1] ?? "").trim();
    if (!raw && snapshot.errors === 0) return;

    const model = ctx?.model;
    const registry = ctx?.modelRegistry;
    const fallback = () => {
      const body = condense(raw) || (snapshot.errors > 0 ? "algo salió mal" : "se terminó la tarea");
      return clean(snapshot.errors > 0 ? `Hubo un error: ${body}` : body);
    };

    /* No bloquea el asentamiento: la reescritura corre en segundo plano y
       habla cuando termina. */
    void (async () => {
      let line = "";
      if (model && registry?.complete) {
        try {
          const response = await registry.complete(
            model,
            {
              systemPrompt: SYSTEM_PROMPT,
              messages: [
                {
                  role: "user" as const,
                  content: [
                    {
                      type: "text" as const,
                      text:
                        (raw || "La tarea terminó sin respuesta textual.") +
                        (snapshot.errors > 0 ? "\n\n[Aviso: hubo un error durante la ejecución.]" : ""),
                    },
                  ],
                  timestamp: Date.now(),
                },
              ],
            },
            { reasoningEffort: "low", cacheRetention: "none", sessionId: uuidv7() },
          );
          line = response.content
            .filter((part): part is { type: "text"; text: string } => part.type === "text")
            .map((part) => part.text)
            .join(" ");
        } catch {
          line = "";
        }
      }
      deliver(line || fallback());
    })();
  });
}
