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
 * Los pendientes viven en `~/.local/share/pi/revisiones.json` (configurable con
 * PI_RIG_DIR).
 */

import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { Type } from "typebox";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const DIR = process.env.PI_RIG_DIR ?? join(homedir(), ".local", "share", "pi");
const ARCHIVO = join(DIR, "revisiones.json");

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

  // -------------------------------------------------------------- command
  pi.registerCommand("revisiones", {
    description: "Lista las revisiones humanas pendientes",
    handler: async (_args, ctx) => {
      ctx.ui.notify(formatoLista(pendientes()), pendientes().length ? "warning" : "info");
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
