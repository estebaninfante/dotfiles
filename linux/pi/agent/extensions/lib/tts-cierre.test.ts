import { test } from "node:test";
import assert from "node:assert/strict";

import { cierreDeCorrida, esInterrupcion, esTextoDeLaCorrida } from "./tts-cierre.ts";

test("cualquier nombre de interrupción cuenta como interrupción", () => {
  for (const r of ["aborted", "interrupted", "cancelled", "canceled", "ABORTED", " aborted "]) {
    assert.equal(esInterrupcion(r), true, r);
  }
  for (const r of ["stop", "end_turn", "toolUse", "length", "error", "", undefined, null]) {
    assert.equal(esInterrupcion(r), false, String(r));
  }
});

test("el texto de la sesión sólo vale si es de esta corrida", () => {
  assert.equal(esTextoDeLaCorrida(1_000, 500), true);
  assert.equal(esTextoDeLaCorrida(500, 1_000), false);
  assert.equal(esTextoDeLaCorrida(undefined, 1_000), true);
});

test("una corrida cortada no se anuncia, aunque el cierre no lo diga", () => {
  // El caso real: `agent_settled` llega con aborted:false pero el turno quedó
  // con stopReason "aborted". Antes esto hablaba igual.
  assert.equal(
    cierreDeCorrida({
      aborted: false,
      turnoInterrumpido: true,
      yaHablado: false,
      aviso: true,
      hayTexto: true,
      errores: 0,
    }),
    "nada",
  );
  assert.equal(
    cierreDeCorrida({
      aborted: true,
      turnoInterrumpido: false,
      yaHablado: false,
      aviso: true,
      hayTexto: true,
      errores: 0,
    }),
    "nada",
  );
});

test("si el agente ya habló, el cierre calla", () => {
  assert.equal(
    cierreDeCorrida({
      aborted: false,
      turnoInterrumpido: false,
      yaHablado: true,
      aviso: true,
      hayTexto: true,
      errores: 0,
    }),
    "nada",
  );
});

test("el aviso del agente gana al resumen de respaldo", () => {
  assert.equal(
    cierreDeCorrida({
      aborted: false,
      turnoInterrumpido: false,
      yaHablado: false,
      aviso: true,
      hayTexto: true,
      errores: 0,
    }),
    "aviso",
  );
});

test("una corrida sin texto ni errores no despierta al usuario", () => {
  assert.equal(
    cierreDeCorrida({
      aborted: false,
      turnoInterrumpido: false,
      yaHablado: false,
      aviso: false,
      hayTexto: false,
      errores: 0,
    }),
    "nada",
  );
});

test("una corrida normal con texto se resume", () => {
  assert.equal(
    cierreDeCorrida({
      aborted: false,
      turnoInterrumpido: false,
      yaHablado: false,
      aviso: false,
      hayTexto: true,
      errores: 0,
    }),
    "resumen",
  );
});

test("un error con algo que contar también se resume", () => {
  assert.equal(
    cierreDeCorrida({
      aborted: false,
      turnoInterrumpido: false,
      yaHablado: false,
      aviso: false,
      hayTexto: false,
      errores: 1,
    }),
    "resumen",
  );
});
