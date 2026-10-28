import { test } from "node:test";
import assert from "node:assert/strict";

import { debeLeer, limpiarParaOido, trocearParaOido } from "./leer.ts";

test("saca lo que no se puede leer en voz alta", () => {
  const entrada = [
    "## Arreglo",
    "",
    "Toqué `auth.json` y quedó así:",
    "",
    "```json",
    '{"OPENCODE_API_KEY": "oc_sk_123"}',
    "```",
    "",
    "| motor | estado |",
    "| --- | --- |",
    "| kokoro | ok |",
    "",
    "- Primero el servidor",
    "- Después la ventana",
    "",
    "Mirá https://ejemplo.com/un/link/larguisimo y ~/.config/LearnHarness/logs/main.log",
  ].join("\n");
  const dicho = limpiarParaOido(entrada);
  assert.equal(dicho.includes("```"), false);
  assert.equal(dicho.includes("oc_sk_123"), false, "el JSON no se dice");
  assert.equal(dicho.includes("|"), false, "la tabla no se dice");
  assert.equal(dicho.includes("https://"), false, "la URL no se dice");
  assert.equal(dicho.includes("main.log"), false, "la ruta no se dice");
  assert.match(dicho, /Arreglo/);
  assert.match(dicho, /auth\.json/);
  assert.match(dicho, /Primero el servidor Después la ventana/);
});

test("el texto vacío o de puro ruido no se lee", () => {
  assert.equal(limpiarParaOido(""), "");
  assert.equal(limpiarParaOido("```\nsolo codigo\n```").trim(), "");
  assert.equal(debeLeer({ activada: true, texto: "" }), false);
  assert.equal(debeLeer({ activada: true, texto: "```\nnpm test\n```" }), false);
});

test("no lee si el usuario cortó o si está apagado", () => {
  const base = { activada: true, texto: "Respuesta completa del agente." };
  assert.equal(debeLeer(base), true);
  assert.equal(debeLeer({ ...base, abortada: true }), false);
  assert.equal(debeLeer({ ...base, turnoInterrumpido: true }), false);
  assert.equal(debeLeer({ ...base, activada: false }), false);
});

test("corta en trozos que no pasan el tope ni rompen palabras", () => {
  const texto =
    "Primera idea sobre el tema. Segunda idea, con una coma, que sigue un rato más. " +
    "Tercera: la que cierra el párrafo y deja claro el punto.";
  const trozos = trocearParaOido(texto, 60, 60);
  assert.ok(trozos.length > 1);
  for (const t of trozos) {
    assert.ok(t.length <= 60, `trozo demasiado largo: ${t.length}`);
    assert.equal(t, t.trim());
  }
  // Nada de palabras partidas: al reunir, el texto queda igual.
  assert.equal(trozos.join(" ").replace(/\s+/g, " "), limpiarParaOido(texto));
});

test("una frase gigante sin puntos se parte igual, sin cortar palabras", () => {
  const palabras = Array.from({ length: 120 }, (_, i) => `palabra${i}`);
  const texto = palabras.join(" ");
  const trozos = trocearParaOido(texto, 50, 50);
  for (const t of trozos) assert.ok(t.length <= 50, `trozo de ${t.length}`);
  assert.deepEqual(trozos.join(" ").split(" "), palabras);
});

test("el primero va corto y el resto agrupado, para sonar enseguida", () => {
  const texto = Array.from({ length: 12 }, (_, i) => `Frase numero ${i}.`).join(" ");
  const trozos = trocearParaOido(texto, 40, 200);
  assert.ok(trozos[0].length <= 40);
  assert.ok(trozos.length <= 3, `no debería mandar ${trozos.length} procesos`);
});
