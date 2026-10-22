import { test } from "node:test";
import assert from "node:assert/strict";

import {
  formatoHora,
  formatoRitmo,
  formatoTokens,
  lineaSesion,
  lineaTurno,
  type TotalesTurno,
} from "./estadisticas.ts";

const totales = (extra: Partial<TotalesTurno> = {}): TotalesTurno => ({
  turnMs: 123_000,
  turnModelMs: 120_000,
  turnTokens: 3400,
  sessionMs: 300_000,
  sessionModelMs: 300_000,
  sessionTokens: 10_000,
  turns: 2,
  endedAt: new Date(2026, 9, 21, 18, 42, 10).getTime(),
  ...extra,
});

test("los tokens se abrevian sin perder la escala", () => {
  assert.equal(formatoTokens(950), "950");
  assert.equal(formatoTokens(3400), "3.4k");
  assert.equal(formatoTokens(24_100), "24k");
  assert.equal(formatoTokens(1_240_000), "1.2M");
  assert.equal(formatoTokens(0), "0");
});

test("el ritmo no inventa números si falta el tiempo o los tokens", () => {
  assert.equal(formatoRitmo(3400, 120_000), "28.3 tok/s");
  assert.equal(formatoRitmo(0, 120_000), undefined);
  assert.equal(formatoRitmo(100, 0), undefined);
});

test("el turno dice duración, tokens, ritmo y hora", () => {
  assert.equal(
    lineaTurno(totales()),
    "2m 03s · 3.4k tok · 28.3 tok/s · terminó 18:42",
  );
  assert.equal(formatoHora(totales().endedAt as number), "18:42");
});

test("la sesión acumula tokens y da el promedio", () => {
  assert.equal(
    lineaSesion(totales()),
    "Sesión 5m 00s · 10k tok · 33.3 tok/s prom.",
  );
});

test("sin turnos cerrados la línea de sesión no se muestra", () => {
  assert.equal(
    lineaSesion(
      totales({ turns: 0, sessionMs: 0, sessionModelMs: 0, sessionTokens: 0 }),
    ),
    undefined,
  );
});
