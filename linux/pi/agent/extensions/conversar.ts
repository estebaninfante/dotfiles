/**
 * conversar — convierte la voz de una sola dirección en una conversación.
 *
 * `tts-summary.ts` ya hace que el agente HABLE (`avisar`). Esta extensión agrega
 * las dos piezas que faltan:
 *
 *  1. Tool `hablar`: el agente LE HABLA al usuario (un avance, contexto o una
 *     explicación) y, si hace falta, ESPERA su respuesta hablada. Primero dice
 *     el contexto y después la pregunta: no se limita a preguntar. Usa el bus
 *     `agente` (hablar / preguntar → esperar), que reutiliza el daemon de voz
 *     (`voice send --agent <nombre>`) y serializa varios agentes.
 *
 *  2. Subtítulos de trabajo: mientras el modelo piensa, un widget de la UI
 *     muestra, en una sola fila, el agente y la tarea que está haciendo (con
 *     el id que le puso `rig.ts`), hace cuánto trabaja y el pensamiento en
 *     vivo en trozos legibles. Así el usuario puede seguirle el paso sin
 *     depender de la voz.
 *
 *     El widget es el ÚNICO visor del pensamiento en vivo: el bloque nativo de
 *     pi se oculta con `hideThinkingBlock` (Ctrl+T lo muestra cuando haga
 *     falta), para no leer lo mismo dos veces.
 *
 * El bus vive en ~/developing/voz-agentes/agente (configurable con PI_AGENTE_BIN).
 * El nombre del agente (que decide su voz) sale de PI_VOICE_AGENT (default "pi").
 *
 * El widget de latido muestra, mientras el modelo trabaja:
 *   - Hace cuánto piensa: por turno y acumulado de la sesión, en horas,
 *     minutos y segundos según corresponda.
 *   - El agente y su tarea (título + id) en una sola fila, para ver de un
 *     vistazo en qué anda cada terminal.
 *   - Los subtítulos del pensamiento: se toma una oración corta y se deja fija
 *     en pantalla; se ilumina palabra por palabra al ritmo de lectura. El
 *     párrafo no se mueve ni cambia: recién cuando se termina de iluminar
 *     entra el siguiente. Si el modelo piensa mucho más rápido de lo que se
 *     puede leer, el ritmo acelera un poco y, si aun así sobra cola, se
 *     descartan las oraciones más viejas para no quedar atrasado.
 *   - El código se saca de los subtítulos (bloques e inline), y los fragmentos
 *     que quedan partidos se descartan en vez de mostrarse rotos.
 *
 * Nombre del agente: decide su voz, su rol, su color y a quién le hablás. Se
 * resuelve solo y se registra en el panel de tmux, así cada agente que abrís ya
 * tiene nombre. Prioridad del nombre: PI_VOICE_AGENT > nombre del panel >
 * carpeta del proyecto > nombre al azar (lista propia). El rol sale de
 * PI_AGENT_ROLE o del propio nombre (main, audio, dotfiles…). Además publica
 * @agent_status, @agent_goal, @agent_role y @agent_color, y pinta el fondo del
 * panel con el color del agente, para que `agente-pane list/info` muestre quién
 * es, en qué anda y dónde está, y para reconocer la terminal de un vistazo.
 *
 * La identidad se guarda en la conversación (entrada `agent-identity`), así al
 * reanudarla vuelven el mismo nombre, rol, color y voz aunque cambie el panel,
 * la carpeta o el proceso; y la tarea (`@agent_goal`) se restaura del último
 * pedido de la propia sesión.
 *
 * Config (archivo ~/.config/pi/latido.json o variables de entorno; la variable
 * gana):
 *   PI_AGENTE_BIN        ruta al bus (default ~/developing/voz-agentes/agente)
 *   PI_VOICE_AGENT       fuerza el nombre/voz del agente
 *   PI_LATIDO=0          apaga el latido
 *   PI_LATIDO_LINES      oraciones visibles a la vez (default 3)
 *   PI_LATIDO_PARAGRAPH_WORDS  palabras tope por oración (default 28)
 *   PI_LATIDO_WORD_MS    ritmo de lectura, ms por palabra (default 150)
 *   PI_LATIDO_FAST_WORD_MS  ritmo acelerado cuando hay cola (default 100)
 *   PI_LATIDO_CATCHUP    palabras de cola que activan el ritmo rápido (default 40)
 *   PI_LATIDO_BACKLOG    máximo de palabras en espera antes de descartar (default 90)
 *   PI_LATIDO_TITLE_CHARS  largo máximo del título de tarea (default 52)
 *   PI_LATIDO_PROMPT_CHARS  largo máximo del pedido de respaldo (default 96)
 */

import { execFileSync, spawn } from "node:child_process";
import { appendFileSync, readFileSync } from "node:fs";
import { basename } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
  esCodigo,
  formatoDuracion,
  limpiarPensamiento,
  oracionUtil,
  recortar,
} from "./lib/pensamiento.ts";

const HOME = process.env.HOME ?? "";
const AGENTE_BIN = process.env.PI_AGENTE_BIN ?? `${HOME}/developing/voz-agentes/agente`;

const TMUX_PANE = process.env.TMUX_PANE?.trim() ?? "";

/** Tipo de entrada de sesión donde vive la identidad del agente: así el nombre,
 *  el rol, el color y la voz quedan atados a la conversación y vuelven al
 *  reanudarla, aunque cambie el panel, la carpeta o el proceso. */
const IDENTITY_ENTRY_TYPE = "agent-identity";

/** Corre tmux sin romper si no hay servidor; devuelve stdout o "". */
function tmux(args: string[]): string {
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

/** Deja el nombre apto para panel/voz: minúsculas, guiones, sin adornos. */
function sanitizeName(raw: string): string {
  return String(raw ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 24);
}

/** Nombres de reserva: si la carpeta no da un nombre único, cada agente recibe
 *  uno al azar y estable mientras viva su panel. */
const NAME_POOL = [
  "andino", "quetzal", "condor", "pampa", "ombu", "yaguar", "colibri",
  "zorro", "puma", "nandu", "tucan", "jaguar", "alpaca", "vicuna",
  "carpincho", "hornero", "lechuza", "halcon", "tordo", "peludo",
  "comadreja", "mulita", "flamenco", "cardenal",
];

let agentNameCache: string | undefined;

/** Identidad estable del agente (nombre, rol y color). Sale del sistema de voz
 *  (`voice identity --json`), la misma fuente que usan los subtítulos del glow
 *  y la barra: así el color del agente es el mismo en todos lados. */
interface AgentIdentity {
  name: string;
  role: string;
  color: string;
  voice: string;
}

function voiceBin(): string {
  return process.env.PI_TTS_VOICE_BIN ?? `${HOME}/.local/bin/voice`;
}

function normHex(value: unknown): string {
  const v = String(value ?? "").trim();
  return /^#[0-9a-fA-F]{6}$/.test(v) ? v.toLowerCase() : "";
}

/** Oscurece un color mezclándolo con negro (para fondos de panel). */
function tint(hex: string, amount = 0.18): string {
  const m = /^#?([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$/.exec(hex);
  if (!m) return hex;
  const mix = (h: string) => Math.max(0, Math.min(255, Math.round(parseInt(h, 16) * amount)));
  const to = (n: number) => n.toString(16).padStart(2, "0");
  return `#${to(mix(m[1]!))}${to(mix(m[2]!))}${to(mix(m[3]!))}`;
}

/** Secuencia ANSI truecolor (respaldo si el tema no acepta un color concreto). */
function truecolorFg(hex: string): string {
  const c = normHex(hex);
  if (!c) return "";
  const r = parseInt(c.slice(1, 3), 16);
  const g = parseInt(c.slice(3, 5), 16);
  const b = parseInt(c.slice(5, 7), 16);
  return `\x1b[38;2;${r};${g};${b}m`;
}

function resolveIdentity(name: string, roleHint = "", reclamar = false): AgentIdentity {
  const fallbackRole = process.env.PI_AGENT_ROLE?.trim() || roleHint || "general";
  const fallback: AgentIdentity = {
    name,
    role: fallbackRole,
    color: "#7dcfff",
    voice: "",
  };
  try {
    const args = ["identity", name];
    if (fallbackRole) args.push("--role", fallbackRole);
    // Al arrancar se RECLAMA un color libre entre los agentes vivos: nunca se
    // repite el color de otro panel. El reclamo se guarda en el registro de
    // identidades, así el nombre conserva ese color la próxima vez.
    if (reclamar) {
      args.push("--claim");
      if (TMUX_PANE) args.push("--pane", TMUX_PANE);
    }
    args.push("--json");
    const out = execFileSync(voiceBin(), args, {
      encoding: "utf8",
      timeout: 2500,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    const j = JSON.parse(out) as Partial<AgentIdentity>;
    return {
      name: String(j.name ?? name) || name,
      role: String(j.role ?? "") || fallbackRole,
      color: normHex(j.color) || fallback.color,
      voice: String(j.voice ?? ""),
    };
  } catch {
    return fallback;
  }
}

/** Rol sugerido por la carpeta del proyecto (mismo criterio que el nombre):
 *  dos agentes del mismo proyecto comparten rol aunque tengan nombres
 *  distintos. Se puede forzar con PI_AGENT_ROLE. */
function projectRole(): string {
  const explicit = process.env.PI_AGENT_ROLE?.trim();
  if (explicit) return explicit;
  try {
    const cwd = process.cwd();
    if (cwd && cwd !== HOME && !cwd.startsWith("/tmp") && !cwd.startsWith(`${HOME}/.`)) {
      const role = sanitizeName(basename(cwd));
      if (role) return role;
    }
  } catch {
    /* sin cwd */
  }
  return "general";
}

let identityCache: AgentIdentity | undefined;

/** Identidad del agente actual (cacheada). */
function agentIdentity(): AgentIdentity {
  return (identityCache ??= resolveIdentity(agentName(), projectRole()));
}

/** Identidad guardada en la conversación (entry custom), si la hay. Se busca en
 *  la rama activa para que un fork herede la identidad de su historia. */
function readStoredIdentity(ctx: unknown): AgentIdentity | undefined {
  try {
    const sm = (ctx as {
      sessionManager?: { getBranch?: () => unknown[]; getEntries?: () => unknown[] };
    })?.sessionManager;
    const entries = (sm?.getBranch?.() ?? sm?.getEntries?.() ?? []) as Array<{
      type?: string;
      customType?: string;
      data?: Partial<AgentIdentity>;
    }>;
    for (let i = entries.length - 1; i >= 0; i--) {
      const e = entries[i];
      if (e?.type !== "custom" || e.customType !== IDENTITY_ENTRY_TYPE) continue;
      const d = e.data ?? {};
      const name = String(d.name ?? "").trim();
      if (!name) continue;
      return {
        name,
        role: String(d.role ?? "").trim() || "general",
        color: normHex(d.color) || "#7dcfff",
        voice: String(d.voice ?? ""),
      };
    }
  } catch {
    /* sin sesión: no importa */
  }
  return undefined;
}

function sameIdentity(a: AgentIdentity, b: AgentIdentity): boolean {
  return a.name === b.name && a.role === b.role && a.color === b.color && a.voice === b.voice;
}

/** Deja el panel de tmux con la identidad dada (nombre, rol, color y fondo). */
function applyIdentityToPane(ident: AgentIdentity): void {
  if (!TMUX_PANE) return;
  tmux(["set-option", "-p", "-t", TMUX_PANE, "@agent_name", ident.name]);
  tmux(["set-option", "-p", "-t", TMUX_PANE, "@agent_role", ident.role]);
  tmux(["set-option", "-p", "-t", TMUX_PANE, "@agent_color", ident.color]);
  tmux(["select-pane", "-t", TMUX_PANE, "-P", `bg=${tint(ident.color, 0.18)}`]);
}

/** Pinta el panel de tmux con el color del agente: fondo y borde llevan SU
 *  color, así la terminal entera se reconoce de un vistazo. Es lo más cerca del
 *  "fondo del agente" que permite tmux cuando varios agentes comparten ventana.
 *  El fondo se oscurece para que el texto siga legible. */
function applyPaneLook(name: string): AgentIdentity {
  const ident = resolveIdentity(name, projectRole(), true);
  identityCache = ident;
  applyIdentityToPane(ident);
  return ident;
}

/** Si OTRO agente vivo quedó con el mismo color (por ejemplo, porque ya estaba
 *  abierto antes de esta regla), reclama uno libre y repinta este panel. Se
 *  corre al empezar cada turno, así los agentes abiertos se corrigen solos sin
 *  reiniciarlos. */
function reclamarColorSiRepetido(): AgentIdentity | undefined {
  const ident = identityCache;
  if (!ident || !TMUX_PANE) return undefined;
  const filas = tmux([
    "list-panes",
    "-a",
    "-F",
    "#{pane_id}\t#{@agent_name}\t#{@agent_color}",
  ]);
  let repetido = false;
  for (const fila of filas.split("\n")) {
    const [pane, name, color] = fila.split("\t");
    if (!pane || pane === TMUX_PANE || !name) continue;
    if (normHex(color) === normHex(ident.color)) {
      repetido = true;
      break;
    }
  }
  if (!repetido) return undefined;
  const reclamada = resolveIdentity(ident.name, ident.role, true);
  identityCache = reclamada;
  applyIdentityToPane(reclamada);
  return reclamada;
}

/** Nombre automático del agente. Prioridad: PI_VOICE_AGENT > nombre del panel
 *  > carpeta del proyecto > nombre al azar. Se registra en el panel de tmux
 *  para que `agente-pane list/focus <nombre>` funcione solo, sin nombrar nada
 *  a mano. Así cada agente que abrís ya tiene nombre y podés saltar a él. */
function ensureAgentName(): string {
  if (agentNameCache) return agentNameCache;

  const explicit = process.env.PI_VOICE_AGENT?.trim();
  if (explicit) {
    if (TMUX_PANE) tmux(["set-option", "-p", "-t", TMUX_PANE, "@agent_name", explicit]);
    applyPaneLook(explicit);
    return (agentNameCache = explicit);
  }
  if (TMUX_PANE) {
    const existing = tmux(["display-message", "-p", "-t", TMUX_PANE, "#{@agent_name}"]);
    if (existing) {
      applyPaneLook(existing);
      return (agentNameCache = existing);
    }
  }

  const used = new Set(
    tmux(["list-panes", "-a", "-F", "#{@agent_name}"])
      .split("\n")
      .map((s) => s.trim())
      .filter(Boolean),
  );
  const cwd = process.cwd();
  const base =
    cwd && cwd !== HOME && !cwd.startsWith("/tmp") && !cwd.startsWith(`${HOME}/.`)
      ? sanitizeName(basename(cwd))
      : "";
  let candidate = base && !used.has(base) ? base : "";
  if (!candidate) {
    const free = NAME_POOL.filter((n) => !used.has(n));
    candidate = free.length
      ? free[Math.floor(Math.random() * free.length)]!
      : NAME_POOL[Math.floor(Math.random() * NAME_POOL.length)]!;
  }
  let name = candidate;
  let i = 2;
  while (used.has(name)) name = `${candidate}-${i++}`;

  if (TMUX_PANE) tmux(["set-option", "-p", "-t", TMUX_PANE, "@agent_name", name]);
  applyPaneLook(name);
  return (agentNameCache = name);
}

/** Lazy: no toca tmux al cargar la extensión, recién cuando hace falta. */
function agentName(): string {
  return ensureAgentName();
}

const LATIDO_ENABLED = process.env.PI_LATIDO !== "0";

interface LatidoConfig {
  lines: number;
  paragraphWords: number;
  wordMs: number;
  fastWordMs: number;
  catchup: number;
  backlog: number;
  titleChars: number;
  promptChars: number;
}

function num(v: unknown, fallback: number): number {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

/** Config del latido: ~/.config/pi/latido.json y luego variables de entorno (la
 *  variable gana). Permite ajustar oraciones, velocidad y foco sin tocar el
 *  código. */
function readLatidoConfig(): LatidoConfig {
  let file: Record<string, unknown> = {};
  try {
    file = JSON.parse(readFileSync(`${HOME}/.config/pi/latido.json`, "utf8"));
  } catch {
    /* sin archivo: quedan los valores por defecto */
  }
  const env = process.env;
  const wordMs = Math.max(60, num(env.PI_LATIDO_WORD_MS ?? file.wordMs, 150));
  const backlog = Math.max(24, num(env.PI_LATIDO_BACKLOG ?? file.backlog, 90));
  return {
    lines: Math.min(8, Math.max(1, num(env.PI_LATIDO_LINES ?? file.lines, 3))),
    paragraphWords: Math.max(6, num(env.PI_LATIDO_PARAGRAPH_WORDS ?? file.paragraphWords, 28)),
    wordMs,
    fastWordMs: Math.min(
      wordMs,
      Math.max(55, num(env.PI_LATIDO_FAST_WORD_MS ?? file.fastWordMs, 100)),
    ),
    catchup: Math.max(8, num(env.PI_LATIDO_CATCHUP ?? file.catchup, 40)),
    backlog,
    titleChars: Math.max(20, num(env.PI_LATIDO_TITLE_CHARS ?? file.titleChars, 52)),
    promptChars: Math.max(20, num(env.PI_LATIDO_PROMPT_CHARS ?? file.promptChars, 96)),
  };
}

const CFG = readLatidoConfig();
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

const HABLAR_PARAMS = Type.Object({
  mensaje: Type.String({
    description:
      "Lo que le decís al usuario en voz alta: el contexto, un avance o la " +
      "pregunta. Una o dos frases llanas en español, sin tecnicismos ni rutas. " +
      "Si vas a preguntar algo, PRIMERO contá el contexto y después la pregunta.",
  }),
  esperar: Type.Optional(
    Type.Boolean({
      description:
        "true si necesitás que el usuario te responda por voz y querés " +
        "esperar. false o ausente para solo decir algo y seguir.",
    }),
  ),
  segundos: Type.Optional(
    Type.Number({
      description:
        "Cuánto esperar la respuesta hablada (solo si esperar=true). " +
        "Default 300.",
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
      setTitle?: (title: string) => void;
      theme?: {
        style?: (text: string, options: Record<string, unknown>) => string;
        fg?: (token: string, text: string) => string;
      };
    };
  } | undefined;

  // Tarea actual: la crea `rig.ts` y la anuncia por `rig:tarea`. Acá solo se
  // muestra (agente × título · id) para saber de un vistazo en qué anda.
  let tareaActual: { id: string; titulo: string; estado?: string } | undefined;

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
  let lastBeatLog = 0;
  let lastTitle = ""; // último título de ventana publicado
  let lastChunkAt = 0; // último delta de pensamiento recibido
  let enFence = false; // el stream está dentro de un bloque ``` (se descarta)
  let saltarLinea = false; // descartar el resto de la línea tras abrir un fence
  let lastPrompt = ""; // último pedido del usuario, de respaldo si no hay tarea
  let sessionThinkingMs = 0; // acumulado de la sesión
  let lastTurnMs = 0; // duración del último turno

  /** Normaliza espacios sin romper palabras. */
  function cleanText(s: unknown): string {
    return String(s ?? "").replace(/\s+/g, " ").trim();
  }

  /** Escribe una opción del panel de tmux (si el agente vive en tmux), así
   *  `agente-pane` puede listar quién es, en qué anda y dónde está. */
  function tmuxSet(key: string, value: string): void {
    if (!TMUX_PANE) return;
    tmux(["set-option", "-p", "-t", TMUX_PANE, key, value]);
  }

  /** Recorta por caracteres respetando el límite de palabra. */
  function truncateWords(text: string, max: number): string {
    return recortar(cleanText(text), max);
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

  /** Encola una oración; si el atraso crece, descarta las más viejas. También
   *  ignora fragmentos de código, oraciones partidas y repeticiones. */
  function pushParagraph(text: string): void {
    const clean = cleanText(text);
    if (!clean || esCodigo(clean) || !oracionUtil(clean)) return;
    const w = words(clean);
    if (!w.length) return;
    const ya = (p: string[]) => p.join(" ").toLowerCase();
    const ultima = paragraphs[paragraphs.length - 1];
    if (ultima && ya(ultima) === ya(w)) return;
    if (current && ya(current) === ya(w) && currentIndex < current.length) return;
    paragraphs.push(w);
    let total = paragraphs.reduce((n, p) => n + p.length, 0);
    while (paragraphs.length > 1 && total > CFG.backlog) {
      total -= paragraphs[0].length;
      paragraphs.shift();
      dropped = true;
    }
  }

  /** Posición del final de la palabra número `n` dentro de `text` (para cortar
   *  sin romper palabras ni sumar caracteres invisibles). */
  function finDePalabra(text: string, n: number): number {
    const re = /\S+/g;
    let m: RegExpExecArray | null;
    let i = 0;
    while ((m = re.exec(text))) {
      if (++i >= n) return m.index + m[0].length;
    }
    return text.length;
  }

  /** Sin puntuación durante demasiado tiempo: corta en una coma o punto y coma
   *  cercano al tope, para no partir una frase por la mitad de una palabra. */
  function cortarSinPuntuacion(): string | null {
    if (words(sentenceBuf).length < CFG.paragraphWords) return null;
    const fin = finDePalabra(sentenceBuf, CFG.paragraphWords);
    const ventana = sentenceBuf.slice(0, fin);
    const cortes = [", ", "; ", ": ", " — ", " – "]
      .map((sep) => ventana.lastIndexOf(sep))
      .filter((i) => i > ventana.length * 0.45);
    const corte = cortes.length ? Math.max(...cortes) + 1 : -1;
    if (corte > 0) {
      const trozo = sentenceBuf.slice(0, corte).trim();
      sentenceBuf = sentenceBuf.slice(corte).trimStart();
      return trozo;
    }
    const trozo = sentenceBuf.slice(0, fin).trim();
    sentenceBuf = sentenceBuf.slice(fin).trimStart();
    return trozo;
  }

  /** Saca los bloques ``` y ~~~ aunque vengan partidos en varios deltas. Si
   *  solo llegó media cerca, se descarta hasta que cierre. */
  function quitarFences(chunk: string): string {
    let out = "";
    for (let i = 0; i < chunk.length; ) {
      if (saltarLinea) {
        const nl = chunk.indexOf("\n", i);
        if (nl < 0) return out;
        i = nl + 1;
        saltarLinea = false;
        continue;
      }
      if (chunk.startsWith("```", i) || chunk.startsWith("~~~", i)) {
        enFence = !enFence;
        i += 3;
        if (enFence) saltarLinea = true; // el lenguaje ("ts") no se muestra
        continue;
      }
      if (enFence) {
        i++;
        continue;
      }
      out += chunk[i++];
    }
    return out;
  }

  /** Acumula el pensamiento y cierra oraciones al ritmo en que aparecen.
   *  Los saltos de línea también cierran oración: el pensamiento suele venir
   *  en párrafos cortos y así no se mezclan dos ideas en una línea. */
  function feedThinking(chunk: string): void {
    if (!chunk) return;
    lastChunkAt = Date.now();
    const visible = quitarFences(chunk);
    if (!visible) return;
    sentenceBuf = limpiarPensamiento(sentenceBuf + visible)
      .replace(/\n+/g, ". ")
      .replace(/\s+/g, " ");
    for (;;) {
      // Ojo: "…" no cierra oración; también es el reemplazo de código inline.
      const m = /^(.*?[.!?])(\s+|$)/s.exec(sentenceBuf);
      if (!m) break;
      const sentence = m[1];
      sentenceBuf = sentenceBuf.slice(m[0].length);
      pushParagraph(sentence);
    }
    let trozo: string | null;
    while ((trozo = cortarSinPuntuacion())) pushParagraph(trozo);
  }

  /** Toma la próxima oración de la cola y la deja fija para iluminarla. */
  function startNextParagraph(): void {
    const next = paragraphs.shift();
    if (!next || !next.length) return;
    current = next;
    currentIndex = 0;
    lastRelease = Date.now();
  }

  /** Resalta una palabra con el color del agente. */
  function highlight(word: string): string {
    const color = agentIdentity().color;
    try {
      const styled = uiCtx?.ui?.theme?.style?.(word, {
        fg: color,
        bg: "selectedBg",
        bold: true,
        underline: true,
      });
      if (styled) return styled;
    } catch {
      /* tema sin ese color: usa ANSI truecolor */
    }
    return `${truecolorFg(color)}\x1b[4;7m${word}\x1b[0m`;
  }

  /** Apaga una palabra que aún no se leyó (visible pero tenue, en su color). */
  function muted(word: string): string {
    const color = agentIdentity().color;
    try {
      const styled = uiCtx?.ui?.theme?.fg?.(color as never, word);
      if (styled) return styled;
    } catch {
      /* tema sin ese color: usa ANSI truecolor apagado */
    }
    return `\x1b[2m${truecolorFg(color)}${word}\x1b[0m`;
  }

  /** Pinta un texto con el color del agente (para el nombre/rol y el reloj). */
  function colored(text: string, bold = false): string {
    const color = agentIdentity().color;
    try {
      const styled = uiCtx?.ui?.theme?.style?.(text, { fg: color, bold });
      if (styled) return styled;
    } catch {
      /* tema sin ese color: usa ANSI truecolor */
    }
    return `${bold ? "\x1b[1m" : ""}${truecolorFg(color)}${text}\x1b[0m`;
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

  /** Las oraciones del pensamiento visibles: la actual iluminada y las que
   *  vienen, tenues, para poder seguir la secuencia completa. */
  function thoughtLines(): string[] {
    const out: string[] = [];
    if (current) out.push(snippet());
    for (const p of paragraphs) {
      if (out.length >= CFG.lines) break;
      const t = truncateWords(p.join(" "), 140);
      if (t) out.push(muted(t));
    }
    return out;
  }

  /** Texto tenue para datos secundarios (id de tarea), con el tema actual. */
  function dim(text: string): string {
    try {
      const styled = uiCtx?.ui?.theme?.style?.(text, { fg: "muted" });
      if (styled) return styled;
    } catch {
      /* tema sin muted: ANSI apagado */
    }
    return `\x1b[2m${text}\x1b[0m`;
  }

  /** Encabezado de una sola fila: `agente × título · id`. */
  function headerLine(): string {
    const ident = agentIdentity();
    const titulo = recortar(
      tareaActual?.titulo || lastPrompt || "sin tarea",
      CFG.titleChars,
    );
    const id = tareaActual?.id ? ` ${dim(`· ${tareaActual.id}`)}` : "";
    return `${colored(ident.name, true)} ${dim("×")} ${colored(titulo, true)}${id}`;
  }

  /** Palabras pendientes de leer (lo que falta de la oración actual + cola). */
  function palabrasPendientes(): number {
    const actual = current ? Math.max(0, current.length - currentIndex) : 0;
    return actual + paragraphs.reduce((n, p) => n + p.length, 0);
  }

  /** Ritmo de lectura: cómodo por defecto; si el modelo va muy rápido y la
   *  cola crece, acelera un poco (hasta `fastWordMs`) para no atrasarse. */
  function ritmoLectura(): number {
    const pendientes = palabrasPendientes();
    const fresco = Date.now() - lastChunkAt < 1500;
    if (fresco && pendientes > CFG.catchup) return CFG.fastWordMs;
    if (fresco && pendientes > CFG.catchup / 2) {
      return Math.round((CFG.wordMs + CFG.fastWordMs) / 2);
    }
    return CFG.wordMs;
  }

  /** Muestra/actualiza el widget: agente × tarea, tiempos y pensamiento. */
  function updateLatido(force = false): void {
    const ui = uiCtx?.ui;
    if (!ui) return;
    const now = Date.now();
    const turnMs = working ? now - workStart : lastTurnMs;
    const sessionMs = sessionThinkingMs + (working ? now - workStart : 0);
    const head = working
      ? `⏱ Pensando hace ${formatoDuracion(turnMs)} · Sesión ${formatoDuracion(sessionMs)}`
      : `✓ ${formatoDuracion(lastTurnMs)} · Sesión ${formatoDuracion(sessionThinkingMs)}`;
    const upcoming = paragraphs.slice(0, CFG.lines).map((p) => p.join(" ")).join("|");
    const label = headerLine();
    const key = `${label}|${head}|${currentIndex}|${current ? current.join(" ") : ""}|${upcoming}|${dropped}`;
    if (!force && key === lastRenderedKey) return;
    lastRenderedKey = key;
    lastRender = now;
    const lines = [label, head];
    if (working) lines.push(...thoughtLines());
    try {
      ui.setStatus?.(
        "voz-latido",
        colored(`${tareaActual?.id ? `${tareaActual.id} ` : ""}⏱ ${formatoDuracion(turnMs)}`),
      );
      ui.setWidget?.("voz-latido", lines);
      // El título de la ventana es lo que herdr/la barra muestran arriba:
      // agente × tarea, sin colores para que no se escape ningún ANSI. Solo se
      // toca cuando cambia, no en cada palabra iluminada.
      const title = `${agentIdentity().name} × ${recortar(
        tareaActual?.titulo || lastPrompt || "sin tarea",
        CFG.titleChars,
      )}${tareaActual?.id ? ` · ${tareaActual.id}` : ""}`;
      if (title !== lastTitle) {
        lastTitle = title;
        ui.setTitle?.(title);
      }
    } catch {
      /* sin UI (modo rpc/print): no importa */
    }
  }

  /** Ritmo: ilumina la siguiente palabra cuando toca y mantiene el reloj. */
  function tickLatido(): void {
    if (!working) return;
    const now = Date.now();
    if (!current) startNextParagraph();
    let ritmo = ritmoLectura();
    // Si el proceso estuvo ocupado, no iluminar diez palabras de golpe.
    if (now - lastRelease > ritmo * 3) lastRelease = now - ritmo;
    while (current && now - lastRelease >= ritmo) {
      lastRelease += ritmo;
      currentIndex++;
      if (currentIndex >= current.length) {
        current = null;
        currentIndex = 0;
        if (paragraphs.length) startNextParagraph();
        break;
      }
      ritmo = ritmoLectura();
    }
    updateLatido();
    // Registro de depuración (PI_LATIDO_DEBUG=1): sirve para verificar el
    // latido headless, donde no hay UI que mirar.
    if (now - lastBeatLog >= 2000) {
      lastBeatLog = now;
      beatLog(
        `working=${working} cola=${paragraphs.length} pendientes=${palabrasPendientes()} actual=${current ? current.join(" ") : "-"}`,
      );
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

  /** Al terminar dejamos a la vista el pedido y los tiempos del turno. */
  function settleLatido(): void {
    lastTitle = "";
    current = null;
    currentIndex = 0;
    paragraphs = [];
    sentenceBuf = "";
    dropped = false;
    enFence = false;
    saltarLinea = false;
    lastRenderedKey = "";
    try {
      uiCtx?.ui?.setStatus?.("voz-latido", undefined);
    } catch {
      /* noop */
    }
    updateLatido(true);
  }

  /** Avisa al resto del harness qué se dijo en voz alta, para que `avisar` (u
   *  otra extensión de cierre) no repita lo mismo al terminar la corrida. Solo
   *  se anuncia el `hablar` que no espera respuesta: una pregunta con
   *  `esperar: true` no reemplaza al cierre, así que no debe silenciarlo. */
  function announceSpoken(texto: string): void {
    const t = cleanText(texto);
    if (!t) return;
    try {
      pi.events.emit("voz:hablado", { agente: agentName(), texto: t, at: Date.now() });
    } catch {
      /* sin bus de eventos: el cierre igual no repite por la regla de `avisar` */
    }
  }

  pi.registerTool({
    name: "hablar",
    label: "Hablar al usuario (voz; con esperar, espera respuesta)",
    description:
      "Le habla al usuario por voz. Por defecto solo dice algo: un avance, " +
      "contexto o una explicación. Si `esperar` es true, además ESPERA su " +
      "respuesta hablada y la devuelve como resultado. Es la vía general para " +
      "comunicarte con el usuario por voz. Si el usuario se perdió o pide " +
      "contexto, contale el contexto en `mensaje`; no te limites a preguntar.",
    promptSnippet:
      "Hablar al usuario por voz; con `esperar` espera su respuesta en vez de asumir",
    promptGuidelines: [
      "Para hablarle al usuario por voz usá `hablar`. Sirve para contar un " +
        "avance, dar contexto o preguntar; es la vía general.",
      "Si necesitás una respuesta del usuario, llamá `hablar` con `esperar: true` " +
        "y una pregunta concreta. Si no, dejala sin `esperar`.",
      "Nunca mandes solo una pregunta si tenés contexto para dar: primero el " +
        "contexto en `mensaje`, después la pregunta. Así el usuario no se pierde.",
      "No uses `hablar` para cosas que ya podés resolver leyendo el repositorio " +
        "o la documentación.",
      "No combines `hablar` y `avisar` para cerrar: si ya le hablaste al usuario " +
        "con `hablar` en esta corrida, `avisar` no vuelve a sonar.",
    ],
    parameters: HABLAR_PARAMS,
    async execute(_toolCallId, params, signal) {
      const mensaje = String(params.mensaje ?? "").trim();
      if (!mensaje) {
        return { content: [{ type: "text", text: "Falta el mensaje." }], details: undefined };
      }
      if (params.esperar !== true) {
        const dicho = await execCapture(["hablar", agentName(), mensaje], 15000, signal);
        if (dicho.code === 0) announceSpoken(mensaje);
        return {
          content: [{ type: "text", text: "Dicho al usuario por voz." }],
          details: undefined,
        };
      }
      const segundos = Math.max(10, Number(params.segundos ?? 300) || 300);
      await execCapture(["preguntar", agentName(), mensaje], 15000, signal);
      const answer = await execCapture(
        ["esperar", agentName(), "--timeout", String(segundos)],
        segundos * 1000 + 5000,
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
              `El usuario no respondió en ${segundos}s. Seguí con tu mejor criterio ` +
              "y, cuando puedas, contale con `hablar` qué asumiste.",
          },
        ],
        details: undefined,
      };
    },
  });

  // La tarea la crea `rig.ts` (id, título y trace) y la anuncia por el bus.
  // Acá solo se muestra en el encabezado y se publica en el panel para que
  // `agente-pane list` diga en qué anda cada uno.
  let tareaSesion: string | undefined;
  pi.events.on("rig:tarea", (datos) => {
    const t = datos as {
      id?: string;
      titulo?: string;
      estado?: string;
      session?: string;
      raiz?: string;
    };
    tareaSesion = t?.session;
    tareaActual = t?.id
      ? {
          id: String(t.id),
          titulo: String(t.titulo ?? ""),
          estado: String(t.estado ?? "activa"),
        }
      : undefined;
    if (tareaActual) {
      tmuxSet("@agent_task", tareaActual.id);
      tmuxSet("@agent_task_title", tareaActual.titulo);
      tmuxSet("@agent_ticket", tareaActual.id);
      if (t?.raiz) tmuxSet("@agent_ticket_root", String(t.raiz));
      tmuxSet("@agent_goal", truncateWords(tareaActual.titulo, 80));
    } else {
      tmuxSet("@agent_ticket", "");
    }
    updateLatido(true);
  });

  /** Ruta de la sesión actual, para descartar una tarea de otra conversación. */
  function sessionPathOf(ctx: unknown): string | undefined {
    try {
      const file = (ctx as { sessionManager?: { getSessionFile?: () => unknown } })
        ?.sessionManager?.getSessionFile?.();
      return typeof file === "string" && file ? file : undefined;
    } catch {
      return undefined;
    }
  }

  // Recuerda el último pedido del usuario: es el respaldo cuando `rig.ts` no
  // está cargado o cuando todavía no llegó el id de la tarea.
  pi.on("input", (event) => {
    const e = event as { source?: string; text?: string };
    if (e?.source === "extension") return;
    const t = cleanText(e?.text);
    if (t) {
      lastPrompt = t;
      if (!tareaActual) tmuxSet("@agent_goal", truncateWords(t, 80));
    }
  });

  pi.on("session_start", async (_event, ctx) => {
    uiCtx = ctx;
    // Si la tarea que quedó en memoria es de otra conversación, se descarta.
    // (La de esta sesión la vuelve a anunciar `rig.ts` al arrancar.)
    const sesion = sessionPathOf(ctx);
    if (tareaActual && tareaSesion && sesion && tareaSesion !== sesion) {
      tareaActual = undefined;
    }
    // La identidad vive con la conversación: al reanudar vuelven el mismo
    // nombre, rol, color y voz. Reseteamos la memoria por si cambió la sesión
    // (nueva, reanudada o bifurcada dentro del mismo proceso).
    agentNameCache = undefined;
    identityCache = undefined;

    const forced = Boolean(
      process.env.PI_VOICE_AGENT?.trim() || process.env.PI_AGENT_ROLE?.trim(),
    );
    const stored = readStoredIdentity(ctx);
    if (stored && !forced) {
      // La conversación ya tiene agente: se respetan nombre y rol aunque el
      // panel o la carpeta ahora digan otra cosa. El color sí se reclama de
      // nuevo: si otro agente vivo ya lo tiene, este toma uno libre y queda
      // guardado en la identidad de la conversación.
      identityCache = stored;
      agentNameCache = stored.name;
      const reclamada = resolveIdentity(stored.name, stored.role, true);
      identityCache = reclamada;
      applyIdentityToPane(reclamada);
      if (!sameIdentity(stored, reclamada)) {
        try {
          pi.appendEntry(IDENTITY_ENTRY_TYPE, reclamada);
        } catch {
          /* sesión efímera: se resuelve de nuevo la próxima vez */
        }
      }
    } else {
      agentName(); // resuelve y registra el nombre en el panel (o lo lee)
      const ident = agentIdentity();
      if (!stored || !sameIdentity(stored, ident)) {
        // Primera vez (o identidad forzada distinta): queda guardada acá.
        try {
          pi.appendEntry(IDENTITY_ENTRY_TYPE, ident);
        } catch {
          /* sesión efímera: se resuelve de nuevo la próxima vez */
        }
      }
    }

    const restored = lastUserPrompt(ctx as never);
    if (restored) {
      lastPrompt = restored;
      tmuxSet("@agent_goal", truncateWords(restored, 80));
    }
    tmuxSet("@agent_status", "idle");
    updateLatido(true);
  });

  pi.on("before_agent_start", (_event, ctx) => {
    // Si otro agente vivo tiene el mismo color, este turno arranca con uno
    // libre (y queda guardado en la identidad de la conversación).
    const reclamada = reclamarColorSiRepetido();
    if (reclamada) {
      try {
        pi.appendEntry(IDENTITY_ENTRY_TYPE, reclamada);
      } catch {
        /* sesión efímera */
      }
    }
    // Si un turno anterior no llegó a asentarse, no perdemos su tiempo.
    if (working && workStart) sessionThinkingMs += Date.now() - workStart;
    working = true;
    workStart = Date.now();
    tmuxSet("@agent_status", "working");
    tmuxSet("@agent_since", String(workStart));
    outstanding = false;
    hasThinking = false;
    sentenceBuf = "";
    paragraphs = [];
    current = null;
    currentIndex = 0;
    dropped = false;
    enFence = false;
    saltarLinea = false;
    lastRelease = Date.now();
    lastChunkAt = lastRelease;
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
    tmuxSet("@agent_status", "idle");
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
