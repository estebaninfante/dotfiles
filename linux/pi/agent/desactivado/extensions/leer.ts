/**
 * leer — que la respuesta COMPLETA se diga en voz alta, no un resumen.
 *
 * `tts-summary` habla una frase al cerrar: sirve para avisar que el agente
 * terminó, no para estudiar con audífonos y las manos ocupadas. Esta extensión
 * agrega el otro modo: cuando la corrida termina, se dice entera la última
 * respuesta del asistente, limpia para el oído y troceada para empezar a sonar
 * enseguida.
 *
 * Reglas (las mismas que el resto de la voz):
 *  - Va por `voice say`, o sea por el daemon: la tecla de Windows (`voice stop`)
 *    corta la lectura igual que cualquier mensaje, y el micrófono de Omar
 *    espera a que termine en vez de escucharse a sí mismo.
 *  - Si el usuario cortó la corrida, no se lee: no se habla trabajo a medias.
 *  - Anuncia por el bus `voz:hablado`, así el cierre de `tts-summary` calla y
 *    el final suena UNA sola vez.
 *  - Se apaga con `leer off` (~/.local/state/voice/leer-respuesta.json) o con
 *    el interruptor maestro de la barra (`voice tts`). Sin archivo, arranca
 *    prendida: es lo que el usuario pidió para escuchar mientras hace otra cosa.
 *
 * Config: PI_LEER=0|1 (fuerza), PI_LEER_MAX (tope de cada trozo, 260),
 *         PI_LEER_DRY=1 (no habla; escribe en PI_LEER_DRY_FILE o /tmp/leer-dry.log),
 *         PI_LEER_DEBUG=1 (deja rastro en ~/.pi/agent/leer.log).
 */
import { appendFileSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { debeLeer, limpiarParaOido, trocearParaOido } from "./lib/leer.ts";
import { esInterrupcion } from "./lib/tts-cierre.ts";
import { decirPorVoz } from "./lib/voz.ts";

type Block = { type?: string; text?: string };

const HOME = process.env.HOME ?? homedir();
const CONFIG = process.env.PI_LEER_CONFIG ?? join(HOME, ".local", "state", "voice", "leer-respuesta.json");
const LOG = join(HOME, ".pi", "agent", "leer.log");
const DRY_FILE = process.env.PI_LEER_DRY_FILE ?? "/tmp/leer-dry.log";
const MAX = Number(process.env.PI_LEER_MAX ?? 260) || 260;
/** Un subagente no habla: el usuario ya está escuchando al agente que lo lanzó. */
const SUBAGENTE = process.env.PI_SUBAGENT === "1";

function activada(): boolean {
  const env = process.env.PI_LEER;
  if (env === "0" || env === "false") return false;
  if (env === "1" || env === "true") return true;
  try {
    const j = JSON.parse(readFileSync(CONFIG, "utf8")) as { activado?: unknown };
    return j?.activado !== false; // sin archivo o sin la clave: prendida
  } catch {
    return true;
  }
}

function rastro(linea: string): void {
  if (process.env.PI_LEER_DEBUG !== "1") return;
  try {
    appendFileSync(LOG, `${new Date().toISOString()} ${linea}\n`);
  } catch {
    /* sin log no se pierde nada */
  }
}

function blocks(content: unknown): Block[] {
  return Array.isArray(content) ? (content as Block[]) : [];
}

export default function (pi: ExtensionAPI) {
  let textos: string[] = [];
  let interrumpido = false;
  let anunciado = false;

  const reset = (): void => {
    textos = [];
    interrumpido = false;
    anunciado = false;
  };

  /** Avisa al resto del harness que esta corrida ya se dice entera, para que el
   *  cierre de `tts-summary` no repita el final. Se emite en `turn_end` (que
   *  siempre ocurre antes de `agent_settled`) y no en el cierre: así no depende
   *  del orden en que se cargaron las extensiones. */
  const anunciar = (texto: string): void => {
    if (anunciado) return;
    anunciado = true;
    try {
      pi.events.emit("voz:hablado", { agente: "pi", texto: texto.slice(0, 200), at: Date.now() });
    } catch {
      /* sin bus de eventos: peor caso, se oye también el cierre */
    }
  };

  pi.on("session_start", reset);

  pi.on("message_end", (event) => {
    const m = (event as { message?: { role?: string; stopReason?: string } }).message;
    if (m?.role === "assistant" && esInterrupcion(m.stopReason)) interrumpido = true;
  });

  pi.on("turn_end", (event) => {
    const m = (event as { message?: { content?: unknown; stopReason?: string } }).message;
    if (esInterrupcion(m?.stopReason)) interrumpido = true;
    for (const b of blocks(m?.content)) {
      if (b.type === "text" && typeof b.text === "string" && b.text.trim()) textos.push(b.text);
    }
    const ultima = textos[textos.length - 1] ?? "";
    if (debeLeer({ activada: activada(), turnoInterrumpido: interrumpido, texto: ultima })) {
      anunciar(limpiarParaOido(ultima));
    }
  });

  pi.on("agent_settled", (event) => {
    const corrida = { textos, interrumpido };
    reset();
    if (SUBAGENTE) return;
    const abortada = (event as { aborted?: boolean }).aborted === true;
    const ultima = [...corrida.textos].reverse().find((t) => t.trim()) ?? "";
    if (
      !debeLeer({
        activada: activada(),
        abortada,
        turnoInterrumpido: corrida.interrumpido,
        texto: ultima,
      })
    ) {
      return;
    }
    const dicho = limpiarParaOido(ultima);
    const trozos = trocearParaOido(dicho, MAX);
    if (!trozos.length) return;
    rastro(`leer ${trozos.length} trozo(s), ${dicho.length} caracteres`);

    if (process.env.PI_LEER_DRY === "1") {
      try {
        appendFileSync(DRY_FILE, `${trozos.join("\n---\n")}\n`);
      } catch {
        /* nada que hacer */
      }
      return;
    }
    // El primero va corto para empezar a sonar ya; el resto queda en la cola
    // del daemon (la tecla de Windows la vacía entera).
    for (const trozo of trozos) decirPorVoz(trozo, { source: "pi" });
  });
}
