/**
 * Reglas del cierre hablado, sin tocar procesos ni archivos.
 *
 * Acá se decide si al asentarse una corrida corresponde hablar y con qué
 * (`../../extensions/tts-summary.ts` hace lo impuro: la voz y la sesión).
 *
 * Lo que se arregla acá: un turno interrumpido no se anuncia, y el respaldo
 * que lee la sesión no puede resucitar texto de turnos anteriores (eso hacía
 * que, al cortar una corrida, el agente "volviera" a comentar trabajo viejo).
 *
 * Tests: `node --test lib/tts-cierre.test.ts`.
 */

/** Interrupción del usuario, sea cual sea el nombre que use el proveedor. */
export function esInterrupcion(stopReason: unknown): boolean {
  const r = String(stopReason ?? "")
    .toLowerCase()
    .trim();
  return r === "aborted" || r === "interrupted" || r === "cancelled" || r === "canceled";
}

/** Texto rescatado de la sesión: sólo vale si se escribió en esta corrida. */
export function esTextoDeLaCorrida(timestamp: number | undefined, arranque: number): boolean {
  // Sin fecha no hay forma de descartarlo: se acepta (comportamiento previo).
  if (!timestamp) return true;
  return timestamp >= arranque;
}

export type Cierre = "aviso" | "resumen" | "nada";

/** Qué se dice al asentarse la corrida. `nada` = silencio total. */
export function cierreDeCorrida(estado: {
  /** `aborted` del evento `agent_settled`. */
  aborted: boolean;
  /** Algún turno de la corrida terminó con `stopReason` de interrupción. */
  turnoInterrumpido: boolean;
  /** El agente ya habló con `hablar` en esta corrida. */
  yaHablado: boolean;
  /** El agente llamó a `avisar` en esta corrida. */
  aviso: boolean;
  /** Hay texto propio de esta corrida para resumir. */
  hayTexto: boolean;
  errores: number;
}): Cierre {
  if (estado.aborted || estado.turnoInterrumpido) return "nada";
  if (estado.yaHablado) return "nada";
  if (estado.aviso) return "aviso";
  if (!estado.hayTexto && estado.errores === 0) return "nada";
  return "resumen";
}
