import { test } from "node:test";
import assert from "node:assert/strict";

import { avisarPorVoz } from "./voz.ts";

test("un binario de voz que no existe no rompe el proceso", async () => {
  // El caso real: el symlink de `voice` desaparece un instante (sync de
  // dotfiles) y el `spawn` falla con ENOENT de forma asíncrona. Antes, ese
  // error sin listener mataba la sesión entera de pi.
  const lanzado = avisarPorVoz("probando", { bin: "/no/existe/voice", source: "test" });
  assert.equal(lanzado, true);
  // Si el listener faltara, este await dejaría el proceso con una excepción
  // no capturada y el test fallaría por el runner.
  await new Promise((listo) => setTimeout(listo, 150));
  assert.ok(true);
});

test("un binario que existe y termina enseguida tampoco rompe nada", async () => {
  assert.equal(avisarPorVoz("hola", { bin: "/bin/true", source: "test" }), true);
  await new Promise((listo) => setTimeout(listo, 100));
  assert.ok(true);
});
