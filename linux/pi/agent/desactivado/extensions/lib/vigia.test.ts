import { test } from "node:test";
import assert from "node:assert/strict";

import {
  Detector,
  Presupuesto,
  estaEstancado,
  firmaDeError,
  huellaDe,
  lineaEstado,
  normalizarTexto,
} from "./vigia.ts";

const B = 1_700_000_000_000;

test("la huella ignora ruido que cambia en cada corrida", () => {
  const a = huellaDe("bash", { command: "npm test -- --runInBand", timeout: 120 });
  const b = huellaDe("bash", { command: "npm test  --  --runInBand", timeout: 300 });
  assert.equal(a, b);
  assert.notEqual(a, huellaDe("bash", { command: "npm run build" }));
});

test("la huella no confunde archivos distintos", () => {
  assert.notEqual(huellaDe("read", { path: "a.ts" }), huellaDe("read", { path: "b.ts" }));
});

test("normalizar recorta fechas, uuids y pids", () => {
  const texto = normalizarTexto(
    "job 01a16092-0800-73e5-9be9-5cb3525cbfde pid=1234 2026-10-21T15:26:53.000Z",
  );
  assert.doesNotMatch(texto, /\d{4}-\d{2}-\d{2}T/);
  assert.doesNotMatch(texto, /01a16092/);
  assert.doesNotMatch(texto, /1234/);
});

test("la firma de error junta el mismo fallo con rutas y números distintos", () => {
  const uno = firmaDeError(
    "TypeError: foo is not a function\n    at bar (/home/x/src/a.ts:12:3)",
  );
  const dos = firmaDeError(
    "TypeError: foo is not a function\n    at bar (/home/y/other/a.ts:90:7)",
  );
  assert.equal(uno, dos);
  assert.match(uno, /typeerror/);
});

test("la firma prefiere la línea de error y no el stack", () => {
  const firma = firmaDeError("running...\n  at foo.js:1:2\nError: ENOENT: no such file or directory");
  assert.match(firma, /enoent/);
});

test("bloquea la tercera vez que falla exactamente la misma llamada", () => {
  const d = new Detector({ ventanaMs: 60_000 });
  const entrada = { command: "curl localhost:3000" };
  d.registrar("bash", entrada, false, "curl: (7) Failed to connect", B);
  assert.equal(d.evaluarAntes("bash", entrada, B + 1_000), undefined);
  d.registrar("bash", entrada, false, "curl: (7) Failed to connect", B + 2_000);
  const v = d.evaluarAntes("bash", entrada, B + 3_000);
  assert.ok(v);
  assert.equal(v?.nivel, "freno");
  assert.equal(v?.regla.startsWith("misma-llamada"), true);
  assert.match(v?.mensaje ?? "", /Cambiá de enfoque/);
});

test("una llamada distinta no queda bloqueada por el fallo de otra", () => {
  const d = new Detector({ ventanaMs: 60_000 });
  d.registrar("bash", { command: "curl localhost:3000" }, false, "curl: (7) Failed to connect", B);
  d.registrar("bash", { command: "curl localhost:3000" }, false, "curl: (7) Failed to connect", B + 1);
  assert.equal(d.evaluarAntes("bash", { command: "curl localhost:3001" }, B + 2), undefined);
});

test("cuando el mismo error se repite con llamadas distintas, frena", () => {
  const d = new Detector({ ventanaMs: 60_000, mismoError: 3 });
  d.registrar("bash", { command: "npm run dev" }, false, "Error: EADDRINUSE: address already in use", B);
  d.registrar("bash", { command: "npm run start" }, false, "Error: EADDRINUSE: address already in use", B + 1);
  d.registrar("bash", { command: "node server.js" }, false, "Error: EADDRINUSE: address already in use", B + 2);
  const v = d.evaluarAntes("bash", { command: "otra cosa" }, B + 3);
  assert.equal(v?.nivel, "freno");
  assert.equal(v?.regla.startsWith("mismo-error"), true);
});

test("un éxito corta la racha de fallos", () => {
  const d = new Detector({ ventanaMs: 60_000, rachaRoja: 3 });
  d.registrar("bash", { command: "a" }, false, "Error: x", B);
  d.registrar("bash", { command: "b" }, false, "Error: y", B + 1);
  d.registrar("bash", { command: "c" }, true, "", B + 2);
  d.registrar("bash", { command: "d" }, false, "Error: z", B + 3);
  assert.equal(d.evaluarAntes("bash", { command: "e" }, B + 4), undefined);
});

test("rachas largas de fallos frenan aunque ningún error se repita", () => {
  const d = new Detector({ ventanaMs: 60_000, rachaRoja: 4, mismoError: 99 });
  for (let i = 0; i < 4; i += 1) {
    d.registrar("bash", { command: `intento-${i}` }, false, `Error distinto ${"x".repeat(i + 1)}`, B + i);
  }
  const v = d.evaluarAntes("bash", { command: "otro" }, B + 10);
  assert.equal(v?.nivel, "freno");
  assert.equal(v?.regla, "racha-roja");
});

test("una tarea que funciona no se bloquea", () => {
  const d = new Detector({ ventanaMs: 60_000 });
  for (let i = 0; i < 20; i += 1) {
    d.registrar("bash", { command: `git status` }, true, "", B + i * 100);
    assert.equal(d.evaluarAntes("bash", { command: `git status` }, B + i * 100 + 50)?.nivel === "freno", false);
  }
});

test("el presupuesto avisa al 70% y frena al 150%", () => {
  const p = new Presupuesto();
  p.limites = { minutos: 10, llamadas: 100, costo: 2 };
  p.iniciar(B);
  p.llamadas = 75;
  assert.equal(p.estado(B + 60_000).nivel, "aviso");
  p.llamadas = 160;
  assert.equal(p.estado(B + 60_000).nivel, "freno");
});

test("el presupuesto mira también minutos y costo", () => {
  const p = new Presupuesto();
  p.limites = { minutos: 10, llamadas: 100, costo: 2 };
  p.iniciar(B);
  p.costo = 1.5;
  const e = p.estado(B + 1_000);
  assert.equal(e.limite, "costo");
  assert.equal(e.nivel, "aviso");
});

test("no se declara estancamiento antes de tiempo ni sin errores", () => {
  assert.equal(
    estaEstancado({ minutosSinAvance: 9, llamadasSinAvance: 30, llamadasTotales: 40, errores: 5 }),
    false,
  );
  assert.equal(
    estaEstancado({ minutosSinAvance: 20, llamadasSinAvance: 30, llamadasTotales: 40, errores: 0 }),
    false,
  );
  assert.equal(
    estaEstancado({ minutosSinAvance: 20, llamadasSinAvance: 30, llamadasTotales: 40, errores: 2 }),
    true,
  );
});

test("la línea de estado es compacta y legible", () => {
  assert.equal(
    lineaEstado({ minutos: 12.6, llamadas: 34, errores: 3, tokens: 48_000, costo: 0.12 }),
    "12m · 34 llam · 3 err · 48k tok · $0.12",
  );
});
