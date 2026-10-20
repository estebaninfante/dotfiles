/**
 * espacios — cada agente trabaja en su propio espacio del escritorio.
 *
 * Varios agentes viven a la vez en la misma sesión gráfica. Si uno abre un
 * navegador o un video, la ventana aparece encima de lo que el usuario está
 * haciendo. Este extension le da a cada sesión de pi **su espacio** (un
 * workspace de Hyprland fuera de la rotación normal, sin foco) y un directorio
 * de atajos que adelanta el `PATH`: así `xdg-open`, el navegador, el visor de
 * imágenes y mpv abren dentro de ese espacio sin que el agente tenga que
 * acordarse.
 *
 * La fuente de verdad es el comando `espacios` (`~/.local/bin/espacios`), que
 * registra al agente, crea la regla de ventana por clase (`agente-<slug>`) y
 * lanza las apps. Acá sólo se conecta la sesión de pi con ese comando.
 *
 * Excepción explícita: **el sonido no se aísla**. Avisos, voz y notificaciones
 * son globales a propósito: el usuario los tiene que oír esté donde esté.
 *
 * Interruptor: PI_ESPACIOS=0 lo desactiva. Si no hay escritorio (no hay
 * HYPRLAND_INSTANCE_SIGNATURE), no hace nada.
 */

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { basename, join } from "node:path";
import { Type } from "typebox";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const HOME = process.env.HOME ?? "";
const ESPACIOS = process.env.PI_ESPACIOS_BIN ?? join(HOME, ".local/bin/espacios");

interface Espacio {
  slug: string;
  espacio: number;
  color: string;
  clase: string;
  shims: string;
}

let espacio: Espacio | undefined;

/** ¿Tiene sentido aislar ventanas acá? */
function hayEscritorio(): boolean {
  if (process.env.PI_ESPACIOS === "0") return false;
  return existsSync(ESPACIOS) && !!process.env.HYPRLAND_INSTANCE_SIGNATURE;
}

function correr(args: string[], timeout = 6000): string {
  try {
    return execFileSync(ESPACIOS, args, {
      encoding: "utf8",
      timeout,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
}

/** Nombre del agente. Misma prioridad que la voz: PI_VOICE_AGENT, el nombre del
 *  panel de tmux, la carpeta del proyecto; si no, uno atado al proceso. */
function nombreAgente(): string {
  const explicito = process.env.PI_VOICE_AGENT?.trim() || process.env.PI_AGENTE?.trim();
  if (explicito) return explicito;
  const pane = process.env.TMUX_PANE?.trim();
  if (pane) {
    try {
      const nombre = execFileSync("tmux", ["display-message", "-p", "-t", pane, "#{@agent_name}"], {
        encoding: "utf8",
        timeout: 1500,
        stdio: ["ignore", "pipe", "ignore"],
      }).trim();
      if (nombre) return nombre;
    } catch {
      /* sin tmux: seguimos */
    }
  }
  const cwd = process.cwd();
  if (cwd && cwd !== HOME && !cwd.startsWith("/tmp") && !cwd.startsWith(`${HOME}/.`)) {
    const base = basename(cwd).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    if (base) return base;
  }
  return `pi-${process.pid}`;
}

/** Si el PATH ya tiene los atajos de este agente, no se toca. */
function engancharPath(shims: string): void {
  const actual = process.env.PATH ?? "";
  if (actual.split(":").includes(shims)) return;
  process.env.PATH = `${shims}:${actual}`;
}

function aplicar(esp: Espacio): void {
  espacio = esp;
  process.env.PI_AGENTE = esp.slug;
  process.env.PI_AGENTE_WS = String(esp.espacio);
  process.env.PI_AGENTE_COLOR = esp.color;
  process.env.PI_AGENTE_CLASE = esp.clase;
  process.env.PI_AGENTE_SHIMS = esp.shims;
  engancharPath(esp.shims);
}

/** Reclama (o re-confirma) el espacio del agente. Idempotente. */
function sincronizar(): Espacio | undefined {
  if (!hayEscritorio()) return undefined;
  const nombre = nombreAgente();
  const salida = correr(["reclamar", nombre, "--pid", String(process.pid), "--json"]);
  if (!salida) return undefined;
  try {
    const datos = JSON.parse(salida) as Espacio;
    if (!datos?.slug || !datos?.shims) return undefined;
    if (espacio && espacio.slug !== datos.slug) correr(["liberar", espacio.slug]);
    aplicar(datos);
    return datos;
  } catch {
    return undefined;
  }
}

const POLITICA = (esp: Espacio) => `## Tu espacio del escritorio

Esta sesión trabaja en su **propio espacio** del escritorio (workspace ${esp.espacio},
sin foco, color ${esp.color}). Lo que abras no debe interrumpir al usuario:

- Para abrir un navegador o una URL: \`espacios url <url>\`. Nunca \`xdg-open\`, ni el
  navegador a pelo.
- Para abrir cualquier app o ventana: \`espacios abrir -- <comando> [args...]\`.
- Si una ventana tuya quedó en el espacio del usuario: \`espacios mover\`.
- No cambies el workspace activo con \`hyprctl\`, ni abras ventanas de otra forma.

Excepción: **el sonido es global**. Avisos, voz y notificaciones (\`hablar\`,
\`avisar\`, \`notify-send\`, \`paplay\`, \`pw-play\`) se usan normal: el usuario los
tiene que oír.

El estado vive en \`~/.local/share/espacios/agentes.json\`; \`espacios listar\` muestra
quién ocupa qué espacio.

Si mientras explicás querés **señalar** algo en la pantalla de openagents (la app
que ve el usuario), mové tu cursor con \`presencia mover <x> <y> --etiqueta "..."\`
(coordenadas 0..1) y retiralo con \`presencia retirar\` al terminar.`;

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async () => {
    sincronizar();
  });

  pi.on("before_agent_start", (event) => {
    // El nombre puede cambiar en el primer turno (p. ej. lo fija la voz):
    // se re-confirma antes de escribir la política en el prompt.
    const esp = sincronizar() ?? espacio;
    if (esp) event.systemPromptOptions.sections.espacios = POLITICA(esp);
  });

  pi.on("session_shutdown", async () => {
    if (espacio) correr(["liberar", espacio.slug], 3000);
    espacio = undefined;
  });

  pi.registerTool({
    name: "ventana",
    label: "Abrir ventanas en el espacio del agente",
    description:
      "Abre una URL o un programa en el espacio del escritorio de este agente, sin " +
      "robarle el foco al usuario. Usalo en vez de xdg-open o de lanzar apps a mano " +
      "cuando necesites que el usuario vea algo (una página, un video, una vista).",
    promptSnippet: "Abrir una URL o app en mi espacio, sin interrumpir al usuario",
    promptGuidelines: [
      "Cuando necesites mostrar algo en pantalla (navegar, abrir una app o un archivo), " +
        "usá la tool `ventana` (o `espacios url` / `espacios abrir`). Nunca `xdg-open`.",
    ],
    parameters: Type.Object({
      accion: Type.Union([Type.Literal("url"), Type.Literal("abrir"), Type.Literal("listar")], {
        description: "url: navegar; abrir: lanzar un programa; listar: qué agente usa qué espacio",
      }),
      url: Type.Optional(Type.String({ description: "URL a abrir (accion=url)" })),
      comando: Type.Optional(
        Type.String({ description: "Programa y argumentos (accion=abrir), ej. «mpv video.mp4»" }),
      ),
    }),
    async execute(_toolCallId, params) {
      if (!hayEscritorio()) {
        return { content: [{ type: "text", text: "No hay escritorio con espacios en esta sesión." }] };
      }
      const esp = sincronizar();
      if (!esp) {
        return { content: [{ type: "text", text: "No pude reclamar un espacio para este agente." }] };
      }
      const accion = String(params.accion ?? "url");
      if (accion === "listar") {
        return { content: [{ type: "text", text: correr(["listar"]) || "sin agentes" }] };
      }
      if (accion === "url") {
        const url = String(params.url ?? "").trim();
        if (!url) throw new Error("falta url");
        correr(["url", url], 8000);
        return { content: [{ type: "text", text: `Abierto en el espacio ${esp.espacio}: ${url}` }] };
      }
      const comando = String(params.comando ?? "").trim();
      if (!comando) throw new Error("falta comando");
      // Sin shell: se parte por espacios y se ejecuta el programa directo.
      correr(["abrir", "--", ...comando.split(/\s+/)], 9000);
      return { content: [{ type: "text", text: `Abierto en el espacio ${esp.espacio}: ${comando}` }] };
    },
  });
}
