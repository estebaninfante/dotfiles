/**
 * ideas — la fábrica de ideas del usuario.
 *
 * El usuario tira preguntas especulativas todo el tiempo ("¿se podría usar un
 * teléfono viejo para…?", "¿y si el OS corre en el ARM y el portátil es solo
 * pantalla?"). Antes se perdían en el chat. Ahora se capturan solas.
 *
 * Hace tres cosas:
 *
 * 1. **Tool `idea`.** Crear, listar, ver, anotar (la conversación va creciendo
 *    dentro del archivo de la idea), cambiar estado, descartar con motivo,
 *    reabrir. La lógica vive en el CLI `ideas` (~/dotfiles/linux/bin/ideas),
 *    una sola implementación para el agente y para el usuario en la terminal.
 *
 * 2. **Captura automática.** Inyecta en el system prompt la regla: cuando el
 *    pedido es una idea/propuesta y no una tarea, se guarda primero y se
 *    responde después. Sin preguntar permiso.
 *
 * 3. **Comandos.** `/ideas` lista, `/idea IDEA-XXXX` muestra una idea en el
 *    panel, `/idea sin id` lo cierra.
 *
 * Datos: ~/.local/share/pi/ideas/ (index.md + IDEA-XXXX.md por idea).
 */

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { Type } from "typebox";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const DIR = process.env.PI_IDEAS_DIR ?? join(homedir(), ".local", "share", "pi", "ideas");
const CLI =
  process.env.PI_IDEAS_BIN ??
  (existsSync(join(homedir(), ".local", "bin", "ideas"))
    ? join(homedir(), ".local", "bin", "ideas")
    : join(homedir(), "dotfiles", "linux", "bin", "ideas"));

const POLITICA = `## Fábrica de ideas

El usuario no solo pide tareas: también piensa en voz alta. Cuando el mensaje es
una **idea, propuesta o pregunta especulativa** ("¿se podría…?", "¿y si…?",
"¿qué pasaría si…?", "estoy pensando en…", "¿sería viable…?"), eso se **captura**
antes de contestar:

1. Llamá a la tool \`idea\` con \`accion: "nueva"\`: un \`titulo\` corto y concreto,
   \`texto\` con la idea en tus palabras (y el planteo del usuario), \`etiquetas\`
   de dos o tres temas. Si ya existe una idea parecida (\`accion: "listar"\`), no
   dupliques: usá \`accion: "anotar"\` en esa.
2. Después respondé el análisis completo. Si la charla llega a una conclusión,
   medida o riesgo, anotala con \`accion: "anotar"\` en la misma idea: la idea
   crece con su conversación.
3. Si el usuario la descarta o la baja a tierra, \`accion: "descartar"\` con el
   \`motivo\`. Nada se borra: queda archivada y visible con \`listar\`.

No preguntes "¿querés que lo guarde?": se guarda y se sigue. No inventes ideas
que el usuario no dijo, y no captures tareas concretas ("arreglá el bug del
panel"): eso es un ticket, no una idea.`;

function cli(args: string[]): string {
  return execFileSync(CLI, args, { encoding: "utf8", timeout: 20_000 }).trim();
}

function cliArgs(params: Record<string, unknown>): string[] {
  const args: string[] = [];
  const push = (flag: string, valor: unknown) => {
    const v = String(valor ?? "").trim();
    if (v) args.push(flag, v);
  };
  push("-t", params.texto);
  push("-e", params.etiquetas);
  push("-d", params.dudas);
  push("-r", params.riesgo);
  push("-m", params.motivo);
  return args;
}

export default function (pi: ExtensionAPI) {
  // ---------------------------------------------------------------- tool
  pi.registerTool({
    name: "idea",
    label: "Fábrica de ideas",
    description:
      "Captura y administra las ideas del usuario (preguntas especulativas tipo " +
      "'¿se podría…?'). Cada idea es un Markdown con su conversación: crear, listar, " +
      "ver, anotar conclusiones, cambiar estado, descartar con motivo o reabrir. " +
      "Usala SIEMPRE que el pedido sea una idea o propuesta y no una tarea concreta, " +
      "antes de responder.",
    promptSnippet: "Capturar y consultar las ideas del usuario",
    promptGuidelines: [
      "Cada vez que el usuario tire una idea o pregunta especulativa, guardala con " +
        "`idea` (accion nueva) ANTES de responder, sin preguntar permiso.",
      "Si ya hay una idea parecida, anotá en esa (accion anotar) en vez de duplicarla.",
      "Cuando la conversación llegue a una conclusión o medición, anotala en la idea.",
      "Si el usuario descarta una idea, usá accion descartar con el motivo; no borres.",
    ],
    parameters: Type.Object({
      accion: Type.Union(
        [
          Type.Literal("nueva"),
          Type.Literal("listar"),
          Type.Literal("ver"),
          Type.Literal("anotar"),
          Type.Literal("estado"),
          Type.Literal("descartar"),
          Type.Literal("reabrir"),
          Type.Literal("etiquetar"),
          Type.Literal("buscar"),
        ],
        { description: "Qué hacer con la idea" },
      ),
      titulo: Type.Optional(Type.String({ description: "Título corto y concreto (nueva)" })),
      id: Type.Optional(Type.String({ description: "ID de la idea, ej. IDEA-7K2P" })),
      texto: Type.Optional(
        Type.String({ description: "La idea en sí (nueva) o lo que se anota en la conversación (anotar)" }),
      ),
      etiquetas: Type.Optional(Type.String({ description: "Temas separados por coma, ej. hardware,bateria" })),
      dudas: Type.Optional(Type.String({ description: "Duda o riesgo abierto" })),
      riesgo: Type.Optional(Type.String({ description: "Riesgo detectado (anotar)" })),
      motivo: Type.Optional(Type.String({ description: "Por qué se descarta (descartar)" })),
      estado: Type.Optional(
        Type.Union(
          [
            Type.Literal("abierta"),
            Type.Literal("explorando"),
            Type.Literal("promovida"),
            Type.Literal("descartada"),
          ],
          { description: "Estado nuevo (estado)" },
        ),
      ),
      consulta: Type.Optional(Type.String({ description: "Texto a buscar (buscar)" })),
    }),
    async execute(_toolCallId, params) {
      const accion = String(params.accion ?? "listar");
      try {
        let salida = "";
        if (accion === "nueva") {
          const titulo = String(params.titulo ?? "").trim();
          if (!titulo) {
            return {
              content: [{ type: "text", text: "Falta el título de la idea." }],
              details: undefined,
            };
          }
          salida = cli(["nueva", titulo, ...cliArgs(params)]);
        } else if (accion === "listar") {
          salida = cli(["listar", ...(params.estado === "descartada" ? ["--todas"] : [])]);
        } else if (accion === "ver") {
          salida = cli(["ver", String(params.id ?? "")]);
        } else if (accion === "anotar") {
          const texto = String(params.texto ?? "").trim();
          if (!texto) {
            return {
              content: [{ type: "text", text: "Falta lo que hay que anotar." }],
              details: undefined,
            };
          }
          salida = cli(["anotar", String(params.id ?? ""), texto, ...cliArgs(params)]);
        } else if (accion === "estado") {
          salida = cli(["estado", String(params.id ?? ""), String(params.estado ?? "")]);
        } else if (accion === "descartar") {
          salida = cli(["descartar", String(params.id ?? ""), ...cliArgs(params)]);
        } else if (accion === "reabrir") {
          salida = cli(["reabrir", String(params.id ?? "")]);
        } else if (accion === "etiquetar") {
          salida = cli(["etiquetar", String(params.id ?? ""), String(params.etiquetas ?? "")]);
        } else if (accion === "buscar") {
          salida = cli(["buscar", String(params.consulta ?? "")]);
        }
        return {
          content: [{ type: "text", text: salida || "Listo." }],
          details: { accion, dir: DIR },
        };
      } catch (e) {
        const err = e as { stderr?: string; message?: string };
        const detalle = String(err.stderr ?? err.message ?? e).trim();
        return {
          content: [{ type: "text", text: `No pude con la idea: ${detalle}` }],
          details: undefined,
        };
      }
    },
  });

  // ------------------------------------------------------------ comandos
  pi.registerCommand("ideas", {
    description: "Lista las ideas guardadas (/ideas --todas incluye descartadas)",
    handler: async (args, ctx) => {
      const todas = String(args ?? "").includes("todas");
      try {
        ctx.ui.notify(cli(["listar", ...(todas ? ["--todas"] : [])]), "info");
      } catch (e) {
        ctx.ui.notify(`No pude listar las ideas: ${String(e)}`, "error");
      }
    },
  });

  pi.registerCommand("idea", {
    description: "Muestra una idea en el panel (/idea IDEA-XXXX; sin id lo cierra)",
    handler: async (args, ctx) => {
      const pedido = String(args ?? "").trim();
      if (!pedido) {
        ctx.ui.setWidget("ideas-detalle", undefined);
        return;
      }
      try {
        const texto = cli(["ver", pedido]);
        const lineas = texto.split("\n").slice(0, 40).map((l) => l.slice(0, 180));
        ctx.ui.setWidget("ideas-detalle", lineas);
        ctx.ui.notify(`Idea ${pedido} en el panel. /idea sin id lo cierra.`, "info");
      } catch {
        ctx.ui.notify(`No encontré la idea ${pedido}. Probá /ideas.`, "warning");
      }
    },
  });

  // ------------------------------------------------- inyección de regla
  pi.on("before_agent_start", (event) => {
    event.systemPromptOptions.sections.fabrica_de_ideas = POLITICA;
  });
}
