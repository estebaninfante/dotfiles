/**
 * correo — los agentes se ven y se hablan, sin importar el harness.
 *
 * El problema: dos agentes trabajando en el mismo repo no saben uno del otro.
 * Este extiende `rig msg` (que es el que guarda todo, en archivos) para que
 * dentro de pi sea automático:
 *
 * 1. Al arrancar, se registra: nombre, harness, repo/rama/worktree, dónde está
 *    y qué está haciendo. Así otro agente puede verlo con `rig msg ls`.
 * 2. En cada herramienta actualiza su pulso ("bash: pytest", "edit: state.js"),
 *    que es lo que el otro lee para saber qué está pasando.
 * 3. Recibe: los mensajes sin leer entran al prompt de cada turno y, si está
 *    quieto, lo despiertan. Lo que ya se leyó no se repite.
 * 4. Habla: tools `agentes` (quién está vivo y qué hace) y `mensaje` (mandar).
 *
 * La otra punta no necesita pi: `rig msg enviar`/`rig msg leer` funcionan desde
 * opencode, un script o a mano. Si el otro tiene ventana tmux, además se le
 * avisa ahí. Estado en `~/.local/state/rig/correo` (lo maneja rig).
 */

import { watch } from "node:fs";
import { execFileSync } from "node:child_process";
import { homedir } from "node:os";
import { Type } from "typebox";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const RIG = process.env.RIG_BIN ?? `${homedir()}/.local/bin/rig`;
const CADA_PULSO_MS = 15_000;
// Respaldo: si el vigilante de archivos no ve el cambio, igual revisamos.
const CADA_REVISION_OCIOSO_MS = 15_000;
// Anti-bucle: no despertamos por el mismo remitente más de N veces por minuto,
// ni dos veces seguidas en menos de este tiempo, ni por mensajes propios.
const VENTANA_ANTIBUCLE_MS = 60_000;
const MAX_DESPIERTES_POR_REMITENTE = 3;
const MIN_MS_ENTRE_DESPIERTES = 5_000;
// Un mensaje largo se resume; muchos mensajes juntos entran como digest.
const MAX_MENSAJES_POR_ENTREGA = 6;
const BUZON = process.env.RIG_CORREO_DIR
  ? `${process.env.RIG_CORREO_DIR}/buzon`
  : `${homedir()}/.local/state/rig/correo/buzon`;

interface Correo {
  de: string;
  para: string;
  ts: string;
  texto: string;
}

/** Correr rig sin romper nada si no está: el correo nunca frena una sesión. */
function rig(args: string[], input?: string): { ok: boolean; salida: string } {
  try {
    const salida = execFileSync(RIG, args, {
      encoding: "utf8",
      timeout: 20_000,
      stdio: [input === undefined ? "ignore" : "pipe", "pipe", "pipe"],
      input,
      env: process.env,
    });
    return { ok: true, salida: salida.trim() };
  } catch (error) {
    const conSalida = error as { stdout?: string; stderr?: string };
    return { ok: false, salida: `${conSalida.stdout ?? ""}${conSalida.stderr ?? ""}`.trim() };
  }
}

/** El nombre del agente: el que le puso el harness, o el de la ventana tmux. */
function nombrePropio(): string {
  const propio = process.env.RIG_AGENTE?.trim() || process.env.PI_VOICE_AGENT?.trim();
  if (propio) return propio;
  if (process.env.TMUX) {
    try {
      const tmux = execFileSync("tmux", ["display-message", "-p", "#{@agent_name}"], {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
        timeout: 3_000,
      }).trim();
      if (tmux) return tmux;
    } catch {
      /* sin tmux o sin nombre */
    }
  }
  return `pi-${process.pid}`;
}

function resumenDeLlamada(nombre: string, entrada: Record<string, unknown>): string {
  const recortar = (texto: unknown, max = 60) => {
    const limpio = String(texto ?? "").replace(/\s+/g, " ").trim();
    return limpio.length > max ? `${limpio.slice(0, max - 1)}…` : limpio;
  };
  if (nombre === "bash") return `bash: ${recortar(entrada.command, 70)}`;
  if (nombre === "write" || nombre === "edit" || nombre === "read") {
    return `${nombre}: ${recortar(entrada.path, 60)}`;
  }
  if (nombre === "worktree") return `worktree ${String(entrada.accion ?? "")} ${String(entrada.id ?? entrada.ruta ?? "")}`;
  if (nombre === "subagent") return `subagentes: ${recortar(entrada.agent ?? "varios")}`;
  return `${nombre}: ${recortar(JSON.stringify(entrada ?? {}), 60)}`;
}

function textoDelCorreo(pendientes: Correo[]): string {
  const muestra = pendientes.slice(-MAX_MENSAJES_POR_ENTREGA);
  const lineas = muestra.map((m) => `- de **${m.de}** (${m.ts.slice(11, 16)}): ${m.texto}`);
  const resto = pendientes.length - muestra.length;
  return [
    `## Correo de otros agentes`,
    ``,
    resto > 0
      ? `${pendientes.length} mensajes sin leer (los ${resto} más viejos quedan en el buzón):`
      : `${muestra.length} mensaje(s) sin leer:`,
    ...lineas,
    ``,
    `No contestes por reflejo: si es un acuse, una confirmación o no te pide nada, no respondas y seguí con tu tarea. Contestá con la tool \`mensaje\` solo si hay algo que destrabar, una vez por tema, y no respondas a quien te acaba de responder.`,
  ].join("\n");
}

export default function (pi: ExtensionAPI) {
  const nombre = nombrePropio();
  process.env.RIG_AGENTE = nombre;

  let ultimoPulso = 0;
  let revision: ReturnType<typeof setInterval> | undefined;
  let vigilante: ReturnType<typeof watch> | undefined;
  let rebote: ReturnType<typeof setTimeout> | undefined;
  let pendienteDeEntrega = false;
  let ultimoDespertar = 0;
  let ctxActual: ExtensionContext | undefined;
  const despiertes = new Map<string, number[]>();

  const registrar = (ctx: ExtensionContext, tarea: string) => {
    rig([
      "msg", "registrar",
      "--nombre", nombre,
      "--harness", "pi",
      "--cwd", ctx.cwd,
      "--tarea", tarea,
    ]);
  };

  const pulso = (texto: string) => {
    const ahora = Date.now();
    if (ahora - ultimoPulso < CADA_PULSO_MS) return;
    ultimoPulso = ahora;
    rig(["msg", "pulso", texto]);
  };

  const leerPendientes = (marcar: boolean): Correo[] => {
    const args = ["msg", "leer", "--de", nombre, "--json"];
    if (!marcar) args.push("--peek");
    const salida = rig(args);
    if (!salida.ok || !salida.salida) return [];
    try {
      const datos = JSON.parse(salida.salida);
      return Array.isArray(datos) ? (datos as Correo[]) : [];
    } catch {
      return [];
    }
  };

  /** ¿Este remitente puede despertarnos ahora? Corta bucles y avalanchas. */
  const puedeDespertar = (de: string): boolean => {
    if (!de || de === nombre) return false; // nunca por un mensaje propio
    const ahora = Date.now();
    if (ahora - ultimoDespertar < MIN_MS_ENTRE_DESPIERTES) return false;
    const previos = (despiertes.get(de) ?? []).filter((t) => ahora - t < VENTANA_ANTIBUCLE_MS);
    if (previos.length >= MAX_DESPIERTES_POR_REMITENTE) {
      despiertes.set(de, previos);
      return false;
    }
    previos.push(ahora);
    despiertes.set(de, previos);
    ultimoDespertar = ahora;
    return true;
  };

  /** Intenta entregar lo pendiente: solo despierta si hay algo nuevo y sano. */
  const intentarEntrega = () => {
    const ctx = ctxActual;
    if (!ctx || pendienteDeEntrega || !ctx.isIdle()) return;
    const pendientes = leerPendientes(false);
    if (!pendientes.length) return;

    const ajenos = pendientes.filter((m) => m.de && m.de !== nombre);
    if (!ajenos.length) {
      // Todo es correo propio (eco): lo damos por leído para no arrastrarlo.
      leerPendientes(true);
      return;
    }
    const ultimo = ajenos[ajenos.length - 1];
    if (!puedeDespertar(ultimo.de)) return;

    const entregados = leerPendientes(true).filter((m) => m.de && m.de !== nombre);
    if (!entregados.length) return;
    pendienteDeEntrega = true;
    try {
      pi.sendUserMessage(textoDelCorreo(entregados), { deliverAs: "followUp" });
    } catch {
      /* si no se puede entregar ahora, queda en el buzon */
    } finally {
      pendienteDeEntrega = false;
    }
  };

  /** Entrega en cuanto el buzón cambia, sin esperar el turno de revisión. */
  const vigilarBuzon = () => {
    if (vigilante) return;
    try {
      vigilante = watch(BUZON, { persistent: false }, () => {
        if (rebote) clearTimeout(rebote);
        rebote = setTimeout(intentarEntrega, 400);
      });
    } catch {
      /* sin vigilante queda el intervalo */
    }
  };

  pi.on("session_start", async (_event, ctx) => {
    registrar(ctx, "arrancando");
    ctxActual = ctx;
    pendienteDeEntrega = false;

    vigilarBuzon();
    revision ??= setInterval(intentarEntrega, CADA_REVISION_OCIOSO_MS);
  });

  pi.on("tool_result", (event) => {
    pulso(resumenDeLlamada(String(event.toolName), (event.input ?? {}) as Record<string, unknown>));
  });

  pi.on("before_agent_start", (event) => {
    const pendientes = leerPendientes(true).filter((m) => m.de && m.de !== nombre);
    if (pendientes.length) {
      event.systemPromptOptions.sections.correo = textoDelCorreo(pendientes);
    } else {
      delete event.systemPromptOptions.sections.correo;
    }
  });

  pi.on("session_shutdown", async () => {
    if (revision) clearInterval(revision);
    revision = undefined;
    if (vigilante) vigilante.close();
    vigilante = undefined;
    if (rebote) clearTimeout(rebote);
    rebote = undefined;
    ctxActual = undefined;
    rig(["msg", "apagar"]);
  });

  pi.registerTool({
    name: "agentes",
    label: "Agentes vivos",
    description:
      "Lista los agentes vivos: nombre, harness, repo/rama o worktree, y qué está haciendo cada uno. " +
      "Sirve para saber quién más está tocando el mismo repo antes de pisar trabajo.",
    promptSnippet: "Ver qué están haciendo los otros agentes",
    promptGuidelines: [
      "Si vas a tocar un repo donde puede haber otro agente, mirá `agentes` antes y coordiná con `mensaje`.",
    ],
    parameters: Type.Object({
      detalle: Type.Optional(Type.Boolean({ description: "Incluir sin leídos y tiempos" })),
    }),
    async execute(_id, params) {
      const salida = rig(params.detalle ? ["msg", "ls"] : ["msg", "ls", "--porcelain"]);
      return {
        content: [{ type: "text", text: salida.salida || "no hay agentes registrados" }],
        details: {},
        isError: !salida.ok,
      };
    },
  });

  pi.registerTool({
    name: "mensaje",
    label: "Mandar mensaje a otro agente",
    description:
      "Le deja un mensaje a otro agente en su buzon y se lo avisa en su ventana si se puede. " +
      "Usalo para coordinar trabajo en el mismo repo (quién mergea, quién espera, qué falta).",
    promptSnippet: "Mandar un mensaje a otro agente",
    promptGuidelines: [
      "Para coordinar con otro agente usá `mensaje` con texto concreto: qué necesita saber y qué esperás que haga.",
    ],
    parameters: Type.Object({
      para: Type.String({ description: "Nombre del agente destino (ver tool agentes)" }),
      texto: Type.String({ description: "El mensaje, corto y concreto" }),
    }),
    async execute(_id, params) {
      const salida = rig(["msg", "enviar", String(params.para), String(params.texto), "--de", nombre]);
      return {
        content: [{ type: "text", text: salida.salida || "(sin salida)" }],
        details: {},
        isError: !salida.ok,
      };
    },
  });

  pi.registerCommand("correo", {
    description: "Quién está vivo y qué mensajes tenés (/correo [leer|ls])",
    handler: async (args, ctx) => {
      const pedido = String(args ?? "").trim().toLowerCase();
      if (pedido === "leer" || pedido === "inbox") {
        const pendientes = leerPendientes(true);
        ctx.ui.notify(
          pendientes.length
            ? pendientes.map((m) => `· ${m.de}: ${m.texto}`).join("\n")
            : "Sin mensajes nuevos.",
          "info",
        );
        return;
      }
      ctx.ui.notify(rig(["msg", "ls"]).salida || "no hay agentes registrados", "info");
    },
  });
}
