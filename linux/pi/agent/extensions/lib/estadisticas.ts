/**
 * Números del cierre de un turno: cuánto tardó, cuántos tokens movió, a qué
 * ritmo y a qué hora terminó; y el acumulado de la sesión.
 *
 * Vive aparte de `conversar.ts` para poder probarlo sin levantar la UI ni la
 * voz: son cuentas y formatos, nada más.
 */

import { formatoDuracion } from "./pensamiento.ts";

/** Totales que muestra el widget al terminar un turno. */
export type TotalesTurno = {
  /** duración del turno (ms) */
  turnMs: number;
  /** tokens movidos en el turno */
  turnTokens: number;
  /** acumulado de la sesión */
  sessionMs: number;
  sessionTokens: number;
  /** turnos cerrados en la sesión */
  turns: number;
  /** epoch ms del cierre, o null si todavía no terminó ninguno */
  endedAt: number | null;
};

/** Tokens legibles: `950`, `3.4k`, `1.2M`. */
export function formatoTokens(n: number): string {
  if (!Number.isFinite(n) || n <= 0) return "0";
  if (n < 1000) return String(Math.round(n));
  if (n < 1_000_000) {
    const miles = n / 1000;
    return `${miles < 10 ? miles.toFixed(1) : Math.round(miles)}k`.replace(".0k", "k");
  }
  const millones = n / 1_000_000;
  return `${millones < 10 ? millones.toFixed(1) : Math.round(millones)}M`.replace(".0M", "M");
}

/** Tokens por segundo, con un decimal mientras es chico. */
export function formatoRitmo(tokens: number, ms: number): string | undefined {
  if (!(tokens > 0) || !(ms > 0)) return undefined;
  const ritmo = tokens / (ms / 1000);
  const valor = ritmo >= 100 ? Math.round(ritmo) : Math.round(ritmo * 10) / 10;
  return `${valor} tok/s`;
}

/** Hora local de un epoch ms: `18:42`. */
export function formatoHora(ms: number): string {
  const fecha = new Date(ms);
  return `${String(fecha.getHours()).padStart(2, "0")}:${String(fecha.getMinutes()).padStart(2, "0")}`;
}

/** `2m 03s · 3.4k tok · 28 tok/s · terminó 18:42` */
export function lineaTurno(t: TotalesTurno): string {
  const partes = [formatoDuracion(t.turnMs)];
  if (t.turnTokens > 0) partes.push(`${formatoTokens(t.turnTokens)} tok`);
  const ritmo = formatoRitmo(t.turnTokens, t.turnMs);
  if (ritmo) partes.push(ritmo);
  if (t.endedAt) partes.push(`terminó ${formatoHora(t.endedAt)}`);
  return partes.join(" · ");
}

/** `Sesión 10m 12s · 24.1k tok · 24 tok/s prom.` */
export function lineaSesion(t: TotalesTurno): string | undefined {
  if (t.turns === 0 && t.sessionMs <= 0) return undefined;
  const partes = [`Sesión ${formatoDuracion(t.sessionMs)}`];
  if (t.sessionTokens > 0) partes.push(`${formatoTokens(t.sessionTokens)} tok`);
  const ritmo = formatoRitmo(t.sessionTokens, t.sessionMs);
  if (ritmo) partes.push(`${ritmo} prom.`);
  return partes.join(" · ");
}
