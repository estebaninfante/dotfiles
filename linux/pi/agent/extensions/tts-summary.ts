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
 * voz alta más una notificación de escritorio. `avisar` es el CIERRE: si el
 * agente la llama varias veces en una corrida, se dice únicamente el último
 * aviso (así no te suena tres veces lo mismo). Para avisar algo en medio del
 * trabajo está `hablar`, que sí es inmediato.
 *
 * Un solo sonido al final: `conversar.ts` avisa por el bus de extensiones qué
 * se dijo en voz alta con `hablar` (sin `esperar`). Si el agente ya habló, el
 * cierre de `avisar` y el resumen de respaldo callan: el final suena UNA sola
 * vez, sin depender de que los textos se parezcan. Una pregunta con `esperar`
 * no cuenta: el usuario la responde y el cierre sí se oye.
 *
 * Red de seguridad: si el agente no llamó la tool en la corrida, al asentarse
 * Pi (`agent_settled`) un modelo reescribe su última respuesta en una frase
 * llana y la habla. Nunca deja mudo al usuario; nunca dice tecnicismos.
 *
 * Interrupción: si el usuario corta la corrida, NO se habla. Se mira en tres
 * lugares, porque `aborted` en `agent_settled` no siempre llega: el propio
 * evento, el `stopReason: "aborted"` del mensaje del asistente (`message_end`
 * / `turn_end`) y el texto que se rescata de la sesión. Un turno interrumpido
 * además deja mudo el cierre ya en vuelo (el resumen de respaldo corre en
 * segundo plano y podría llegar después del corte) y el silencio dura hasta el
 * próximo pedido del usuario. La voz automática queda reservada a corridas que
 * terminan solas.
 *
 * Interruptor: el `tts.enabled` del sistema de voz (config.toml [tts] + override
 * en state.json). El widget de barra eztvn.pi-tts lo togglea con `voice tts`.
 * Con la voz apagada, `avisar` no se le declara al modelo, `deliver` no llama
 * al sistema de voz y el resumen de respaldo no se genera.
 *
 * Config:
 *   PI_TTS_VOICE_BIN   binario del sistema de voz (default: ~/.local/bin/voice)
 *   PI_TTS_DRY=1       no habla ni notifica; escribe en PI_TTS_DRY_FILE o /tmp
 */

import { execFileSync } from "node:child_process";
import { appendFileSync, readFileSync } from "node:fs";
import { basename } from "node:path";
import { uuidv7 } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { cierreDeCorrida, esInterrupcion, esTextoDeLaCorrida } from "./lib/tts-cierre.ts";
import { avisarPorVoz } from "./lib/voz.ts";

type Block = { type?: string; text?: string };
type Message = { content?: unknown };

type RunSummary = {
  texts: string[];
  errors: number;
  /** Algún turno de la corrida terminó interrumpido (`stopReason: aborted`). */
  aborted: boolean;
};

const MAX_SUMMARY = 240;
const DEDUP_MS = 20000;
const HOME = process.env.HOME ?? "";
const VOICE_STATE = `${HOME}/.local/state/voice/state.json`;

/** Interruptor maestro de voz (`tts.enabled`). Sin estado legible se asume
 *  encendido, como el default de config.toml. */
function ttsEnabled(): boolean {
  try {
    const j = JSON.parse(readFileSync(VOICE_STATE, "utf8")) as {
      tts?: { enabled?: unknown };
    };
    if (typeof j?.tts?.enabled === "boolean") return j.tts.enabled;
  } catch {
    /* sin estado: vale el default */
  }
  return true;
}

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
  // El lanzamiento vive en `lib/voz.ts`: captura el `error` asíncrono del
  // `spawn` (un ENOENT sin listener mataba el proceso entero) y tiene su test.
  avisarPorVoz(line, { source: agentName(), home: HOME });
}

let lastDelivered = "";
let lastDeliveredAt = 0;
/* Tras una interrupción no se habla hasta el próximo pedido del usuario. El
   resumen de respaldo se genera en segundo plano: este cerrojo evita que el
   cierre de una corrida ya cortada suene un rato después del corte. */
let abortedUntilPrompt = false;
let abortEpoch = 0;

/* Dedup: evita repetir la misma frase en pocos segundos (el agente puede
   llamar a `avisar` a mitad y al final). */
function deliver(text: string, limit = MAX_SUMMARY): void {
  if (abortedUntilPrompt) return;
  if (!ttsEnabled()) return;
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
  /* Con la voz apagada, `avisar` ni se le declara al modelo. Se revisa en
     `session_start` y en cada turno, así el toggle de la barra aplica sin
     reiniciar Pi. */
  function syncVoiceTool(): void {
    try {
      const activas = pi.getActiveTools();
      const tiene = activas.includes("avisar");
      if (ttsEnabled()) {
        if (!tiene) pi.setActiveTools([...activas, "avisar"]);
      } else if (tiene) {
        pi.setActiveTools(activas.filter((n) => n !== "avisar"));
      }
    } catch {
      /* API no disponible: queda como está */
    }
  }

  let run: RunSummary = { texts: [], errors: 0, aborted: false };
  /* Marca de tiempo del arranque de la corrida: el respaldo que lee la sesión
     nunca debe resucitar texto de turnos anteriores. */
  let runStartedAt = 0;
  let announced = false;
  // Último aviso de la corrida: `avisar` ya no habla cada vez que lo llaman,
  // sino que se dice al cerrar (gana el último). Así el agente puede reportar
  // avances sin que te suene tres veces lo mismo.
  let pendingAviso = "";
  /* Lo que el agente ya dijo con `hablar` (sin `esperar`) en esta corrida.
     Llega por el bus de extensiones (`conversar.ts` lo emite). Regla dura: si
     el agente ya habló, el cierre (`avisar`) y el resumen de respaldo callan.
     Así el final suena UNA sola vez, sin depender de parecidos de texto. */
  let spokenByHablar: string[] = [];
  try {
    pi.events.on("voz:hablado", (data) => {
      const texto = String((data as { texto?: string })?.texto ?? "").trim();
      if (texto) spokenByHablar.push(texto);
    });
  } catch {
    /* sin bus de eventos: solo queda el dedup interno de `deliver` */
  }

  pi.registerTool({
    name: "avisar",
    label: "Avisar por voz",
    description:
      "Avisa al usuario al cerrar la corrida (el sistema de voz lo habla o lo " +
      "deja en su buzón). Llamala UNA sola vez, cuando ya no vas a hacer más " +
      "trabajo, con una sola frase breve en español natural y respetuoso, como " +
      "quien le reporta un avance a otra persona: qué hiciste y si quedó listo. " +
      "Si la llamás varias veces, solo se dice la última. Para avisar algo en " +
      "medio del trabajo, que el usuario necesite en el momento, usá `hablar`; " +
      "`avisar` es el cierre. Sin tecnicismos, sin rutas, sin nombres de " +
      "herramientas o funciones. No uses apelativos ni lo llames 'jefe'. " +
      "Si necesitás una respuesta, usá `hablar` con `esperar: true`.",
    promptSnippet: "Avisar al usuario al cerrar (voz o buzón; solo se dice el último aviso)",
    promptGuidelines: [
      "Llama a `avisar` UNA vez, al terminar la corrida (cuando ya no vas a " +
        "seguir trabajando), con una sola frase breve en español natural y " +
        "respetuoso (como quien le reporta un avance a otra persona): qué pasó y " +
        "si quedó listo. Si ya le hablaste al usuario con `hablar` en esta " +
        "corrida, `avisar` no vuelve a sonar: no la llames para cerrar. Nunca " +
        "incluyas tecnicismos, rutas ni nombres de herramientas; se dirá en voz " +
        "alta o se dejará en su buzón.",
      "Si necesitás que el usuario te responda, no te quedes en `avisar`: usá " +
        "`hablar` con `esperar: true` y una pregunta concreta, y TERMINÁ el turno " +
        "en el acto (no esperes la respuesta en el momento). `avisar` es para " +
        "reportar, no para preguntar.",
      "Para avisar algo en medio del trabajo, que el usuario necesite AHORA, usá " +
        "`hablar` (inmediato): eso ya cuenta como tu voz en la corrida, así que " +
        "después no hace falta `avisar`. Si lo llamás varias veces, solo se dice " +
        "el último para no repetirte.",
      "No uses apelativos ni la palabra 'jefe': habla directo.",
    ],
    parameters: AVISAR_PARAMS,
    async execute(_toolCallId, params) {
      announced = true;
      // No habla acá: guarda el aviso y se dice al asentarse la corrida (gana
      // el último). Sin tope de largo: ya viene en una frase breve.
      pendingAviso = String(params.mensaje ?? "");
      return {
        content: [{ type: "text", text: "Anotado: se avisa al cerrar la corrida." }],
        details: undefined,
      };
    },
  });

  pi.on("before_agent_start", () => {
    syncVoiceTool();
    announced = false;
    pendingAviso = "";
    // Pedido nuevo: vuelve a habilitarse la voz de cierre.
    abortedUntilPrompt = false;
    run = { texts: [], errors: 0, aborted: false };
    runStartedAt = Date.now();
  });

  /* La interrupción no siempre llega como `aborted` en `agent_settled` (p. ej.
     cuando el corte lo provoca algo que entra a mitad de corrida): el mensaje
     del asistente queda igual con `stopReason: "aborted"`. Eso alcanza para
     callar el cierre de esta corrida y el que quedó en vuelo. */
  pi.on("message_end", (event) => {
    const m = (event as { message?: { role?: string; stopReason?: string } }).message;
    if (m?.role === "assistant" && esInterrupcion(m.stopReason)) {
      run.aborted = true;
      abortedUntilPrompt = true;
      abortEpoch += 1;
      pendingAviso = "";
    }
  });

  pi.on("session_start", () => {
    syncVoiceTool();
    // La identidad vive con la conversación: al reanudar otra, el nombre (y con
    // él la voz y el color) puede cambiar. Se resuelve de nuevo desde el panel.
    agentNameCache = undefined;
    spokenByHablar = [];
    lastDelivered = "";
    abortedUntilPrompt = false;
    run = { texts: [], errors: 0, aborted: false };
  });

  pi.on("turn_end", async (event, ctx) => {
    const message = (event as { message?: Message }).message;
    if (esInterrupcion((message as { stopReason?: string } | undefined)?.stopReason)) {
      run.aborted = true;
      abortedUntilPrompt = true;
      abortEpoch += 1;
      pendingAviso = "";
    }
    for (const block of blocks(message?.content)) {
      if (block.type === "text" && typeof block.text === "string") {
        run.texts.push(block.text);
      }
    }
    const results = (event as { toolResults?: { isError?: boolean }[] }).toolResults ?? [];
    run.errors += results.filter((result) => result?.isError).length;

    /* Respaldo si el evento no trae contenido: leer la última respuesta, pero
       sólo si es de ESTA corrida. Antes se leían los últimos ocho asientos sin
       mirar la fecha: un turno interrumpido (sin texto) terminaba resumiendo
       trabajo viejo ya comentado y te lo volvía a decir por voz. */
    if (!run.texts.length && ctx?.sessionManager) {
      for (const entry of ctx.sessionManager.getEntries().slice(-8)) {
        if (entry.type !== "message" || entry.message.role !== "assistant") continue;
        const when = Number((entry.message as { timestamp?: number }).timestamp ?? 0);
        if (!esTextoDeLaCorrida(when, runStartedAt)) continue;
        if (esInterrupcion((entry.message as { stopReason?: string }).stopReason)) {
          run.aborted = true;
          continue;
        }
        for (const block of blocks(entry.message.content)) {
          if (block.type === "text" && typeof block.text === "string") run.texts.push(block.text);
        }
      }
    }
  });

  pi.on("agent_settled", async (event, ctx) => {
    const snapshot = run;
    run = { texts: [], errors: 0, aborted: false };
    const hadAviso = announced;
    const deferred = pendingAviso;
    announced = false;
    pendingAviso = "";
    /* Consumimos lo que ya se dijo con `hablar` en esta corrida. Si el agente
       ya habló, el usuario ya escuchó: ni el cierre (`avisar`) ni el resumen de
       respaldo vuelven a sonar. Es una regla dura (no un parecido de texto)
       para que el final suene una sola vez. */
    const hablados = spokenByHablar;
    spokenByHablar = [];
    const decision = cierreDeCorrida({
      aborted: (event as { aborted?: boolean }).aborted === true,
      turnoInterrumpido: snapshot.aborted,
      yaHablado: hablados.length > 0,
      aviso: hadAviso,
      hayTexto: Boolean((snapshot.texts[snapshot.texts.length - 1] ?? "").trim()),
      errores: snapshot.errors,
    });
    /* Corrida interrumpida: el usuario ya sabe que cortó; no lo llamamos por
       voz ni le resumimos trabajo a medias. Se mira el evento y también los
       turnos de la corrida, porque `aborted` no siempre viene en el cierre. El
       silencio sigue vigente hasta el próximo pedido (ver `deliver`). */
    if (decision === "nada") {
      if ((event as { aborted?: boolean }).aborted === true || snapshot.aborted) {
        abortedUntilPrompt = true;
        abortEpoch += 1;
      }
      return;
    }
    /* Voz apagada: ni cierre ni resumen de respaldo. */
    if (!ttsEnabled()) return;
    /* El agente ya reportó con `avisar`: se dice SOLO el último aviso de la
       corrida (los anteriores se descartaron) y no corre el resumen de
       respaldo. */
    if (decision === "aviso") {
      const line = deferred.trim();
      if (line) deliver(line, 0);
      return;
    }

    const raw = (snapshot.texts[snapshot.texts.length - 1] ?? "").trim();

    const model = ctx?.model;
    const registry = ctx?.modelRegistry;
    const fallback = () => {
      const body = condense(raw) || (snapshot.errors > 0 ? "algo salió mal" : "se terminó la tarea");
      return clean(snapshot.errors > 0 ? `Hubo un error: ${body}` : body);
    };

    /* No bloquea el asentamiento: la reescritura corre en segundo plano y
       habla cuando termina. Si mientras tanto el usuario interrumpe, se
       descarta: nada de cerrar una corrida que el usuario ya cortó. */
    const epoch = abortEpoch;
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
      if (abortedUntilPrompt || epoch !== abortEpoch) return;
      deliver(line || fallback());
    })();
  });
}
