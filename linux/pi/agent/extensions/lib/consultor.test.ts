import { test } from "node:test";
import assert from "node:assert/strict";

import {
  PREFERIDOS,
  archivosDelHistorial,
  armarDossier,
  elegirConsultor,
  esClaude,
  extraerTexto,
  guiaUtil,
} from "./consultor.ts";

const disponibles = [
  { provider: "opencode", id: "claude-opus-5-5" },
  { provider: "opencode", id: "gpt-6.1-sol" },
  { provider: "opencode", id: "gemini-4-argon" },
  { provider: "opencode-go", id: "grok-4.7" },
  { provider: "opencode-go", id: "deepseek-v4-pro" },
  { provider: "opencode-go", id: "deepseek-v4.1-flash" },
];

test("Claude queda descartado aunque esté disponible", () => {
  assert.equal(esClaude("opencode", "claude-opus-5-5"), true);
  assert.equal(esClaude("anthropic", "cualquier-cosa"), true);
  assert.equal(esClaude("opencode", "gpt-6.1-sol"), false);
  assert.equal(elegirConsultor(disponibles)?.id, "gpt-6.1-sol");
});

test("no elige modelos chicos ni de la misma familia que las manos", () => {
  const elegido = elegirConsultor(disponibles);
  assert.notEqual(elegido?.id, "deepseek-v4.1-flash");
  assert.notEqual(elegido?.id, "grok-4.7"); // hay una opción mejor antes
});

test("respeta el override si tiene credenciales", () => {
  assert.deepEqual(elegirConsultor(disponibles, { override: "opencode-go/grok-4.7" }), {
    provider: "opencode-go",
    id: "grok-4.7",
  });
  // Un override sin credenciales se ignora y se usa la lista.
  assert.equal(elegirConsultor(disponibles, { override: "otro/no-existe" })?.id, "gpt-6.1-sol");
});

test("sin frontera disponible no consulta (salvo que se habilite el medio)", () => {
  const soloMedio = disponibles.filter((m) => m.id === "deepseek-v4-pro" || m.id === "deepseek-v4.1-flash");
  assert.equal(elegirConsultor(soloMedio), undefined);
  assert.equal(elegirConsultor(soloMedio, { permitirMedio: true })?.id, "deepseek-v4-pro");
});

test("saca los archivos involucrados del historial, sin repetir", () => {
  const archivos = archivosDelHistorial([
    { nombre: "read", resumen: "read: src/a.ts" },
    { nombre: "edit", resumen: "edit: src/a.ts" },
    { nombre: "bash", resumen: "bash: npm test" },
    { nombre: "read", resumen: "read: src/b.ts" },
  ]);
  assert.deepEqual(archivos, ["src/a.ts", "src/b.ts"]);
});

test("la lista de preferidos no incluye Claude", () => {
  for (const modelo of PREFERIDOS) {
    assert.equal(esClaude(modelo.provider, modelo.id), false, `${modelo.provider}/${modelo.id}`);
  }
});

test("el dossier es corto, no repite errores y muestra lo intentado", () => {
  const dossier = armarDossier({
    objetivo: "Arreglar el foco del panel",
    intento: "Probar el botón de cerrar",
    problema: "El click no llega al handler",
    siguiente: "Revisar el z-index",
    repo: "pi-desktop",
    rama: "fix-foco",
    modelo: "deepseek-v4.1-flash",
    llamadas: 37,
    errores: 9,
    minutos: 12,
    historial: [
      { nombre: "bash", resumen: "bash: npm test", ok: false, firma: "typeerror: x is not a function", error: "TypeError: x is not a function\n at a.ts:1:1" },
      { nombre: "bash", resumen: "bash: npm test", ok: false, firma: "typeerror: x is not a function" },
      { nombre: "edit", resumen: "edit: src/App.tsx", ok: true },
      { nombre: "bash", resumen: "bash: npm run build", ok: false, firma: "error: cannot find module y" },
    ],
  });
  assert.match(dossier, /OBJETIVO: Arreglar el foco/);
  assert.match(dossier, /YA INTENTÓ/);
  assert.match(dossier, /ERRORES ÚNICOS/);
  const unicos = dossier.slice(dossier.indexOf("ERRORES ÚNICOS"));
  assert.equal(unicos.match(/typeerror: x is not a function/g)?.length, 1); // no se repite en la lista de únicos
  assert.ok(dossier.length <= 3_600);
  assert.doesNotMatch(dossier, /edit: src\/App\.tsx/); // los éxitos no van a "intentó"
});

test("el dossier respeta el tope aunque el error sea enorme", () => {
  const dossier = armarDossier({
    objetivo: "x".repeat(2_000),
    llamadas: 10,
    errores: 4,
    minutos: 3,
    historial: [{ nombre: "bash", ok: false, error: "E".repeat(5_000), firma: "f".repeat(500) }],
  });
  assert.ok(dossier.length <= 3_600);
});

test("extrae solo texto y descarta corridas fallidas", () => {
  const ok = extraerTexto({
    stopReason: "stop",
    content: [
      { type: "thinking", text: "no va" },
      { type: "text", text: "DIAGNÓSTICO: falta el listener" },
    ],
  });
  assert.equal(ok, "DIAGNÓSTICO: falta el listener");
  assert.equal(extraerTexto({ stopReason: "error", content: [{ type: "text", text: "algo" }] }), "");
  assert.equal(extraerTexto(undefined), "");
});

test("una guía vacía o un rechazo no se inyecta", () => {
  assert.equal(guiaUtil(""), false);
  assert.equal(guiaUtil("Lo siento, no puedo ayudar con eso."), false);
  assert.equal(guiaUtil("DIAGNÓSTICO: el handler no está enganchado.\nHACER: 1. revisá X 2. probá Y"), true);
});
