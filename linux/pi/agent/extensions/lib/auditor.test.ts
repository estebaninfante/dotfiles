import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";

import {
  HERRAMIENTAS_AUDITOR,
  ejecutarHerramienta,
  recortarSalida,
  rutaPermitida,
} from "./auditor.ts";

function repoFalso() {
  const base = mkdtempSync(join(tmpdir(), "vigia-auditor-"));
  writeFileSync(join(base, "app.ts"), "export function sumar(a, b) {\n  return a - b;\n}\n");
  writeFileSync(join(base, ".env"), "SECRETO=123\n");
  mkdirSync(join(base, "src"));
  writeFileSync(join(base, "src", "util.ts"), "export const x = 1;\n");
  return base;
}

test("la ruta no puede salir del repo", () => {
  const base = repoFalso();
  try {
    assert.equal(rutaPermitida(base, "app.ts").ok, true);
    assert.equal(rutaPermitida(base, "../afuera.ts").ok, false);
    assert.equal(rutaPermitida(base, "/etc/passwd").ok, false);
    assert.equal(rutaPermitida(base, "src/../app.ts").ok, true);
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});

test("no deja leer secretos ni .git", () => {
  const base = repoFalso();
  try {
    assert.equal(rutaPermitida(base, ".env").ok, false);
    assert.equal(rutaPermitida(base, ".env.local").ok, false);
    assert.equal(rutaPermitida(base, "certs/server.pem").ok, false);
    assert.equal(rutaPermitida(base, ".git/config").ok, false);
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});

test("read_file devuelve líneas numeradas y respeta el rango", async () => {
  const base = repoFalso();
  try {
    const r = await ejecutarHerramienta(base, "read_file", { path: "app.ts", from: 2, lines: 1 });
    assert.equal(r.isError, false);
    assert.match(r.texto, /2 \|   return a - b;/);
    assert.doesNotMatch(r.texto, /export function/);
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});

test("read_file rechaza secretos y rutas de afuera", async () => {
  const base = repoFalso();
  try {
    assert.equal((await ejecutarHerramienta(base, "read_file", { path: ".env" })).isError, true);
    assert.equal((await ejecutarHerramienta(base, "read_file", { path: "../../etc/passwd" })).isError, true);
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});

test("search_repo encuentra el símbolo y no explota con basura", async () => {
  const base = repoFalso();
  try {
    const r = await ejecutarHerramienta(base, "search_repo", { pattern: "sumar" });
    assert.equal(r.isError, false);
    assert.match(r.texto, /app\.ts:1/);
    const feo = await ejecutarHerramienta(base, "search_repo", { pattern: "([" });
    assert.equal(typeof feo.texto, "string");
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});

test("git_review mira estado y diff sin shell libre", async () => {
  const base = repoFalso();
  try {
    execFileSync("git", ["init", "-q"], { cwd: base });
    execFileSync("git", ["add", "."], { cwd: base });
    execFileSync(
      "git",
      ["-c", "user.email=a@b.c", "-c", "user.name=a", "commit", "-qm", "inicial"],
      { cwd: base },
    );
    writeFileSync(join(base, "app.ts"), "export function sumar(a, b) {\n  return a + b;\n}\n");
    const estado = await ejecutarHerramienta(base, "git_review", { action: "status" });
    assert.match(estado.texto, /app\.ts/);
    const diff = await ejecutarHerramienta(base, "git_review", { action: "diff", path: "app.ts" });
    assert.match(diff.texto, /a \+ b/);
    const malo = await ejecutarHerramienta(base, "git_review", { action: "push" });
    assert.equal(malo.isError, true);
  } finally {
    rmSync(base, { recursive: true, force: true });
  }
});

test("recorta la salida y avisa", () => {
  const recortado = recortarSalida("x".repeat(10_000), 1_000);
  assert.ok(recortado.length < 1_100);
  assert.match(recortado, /recortada/);
});

test("las herramientas declaradas son de solo lectura", () => {
  const nombres = HERRAMIENTAS_AUDITOR.map((h) => h.name).sort();
  assert.deepEqual(nombres, ["git_review", "read_file", "search_repo"]);
});
