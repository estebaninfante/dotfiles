/**
 * Verificador de la puerta de merge: corre sin congelar la sesión y vuelve
 * aunque el comando deje procesos vivos atrás.
 *
 * Los tres casos que importan, con comandos falsos (no tocan ningún repo):
 *
 * 1. No bloquea: mientras la puerta corre, los timers del proceso siguen
 *    disparando. Con `execFileSync` esto fallaba (0 ticks) y la ventana de
 *    kitty se veía congelada.
 * 2. Vuelve aunque quede un hijo vivo: `sleep 30 &` no puede retener la
 *    salida, porque no hay pipe que heredar. Antes esto esperaba 30s o para
 *    siempre.
 * 3. Distingue verde, rojo, timeout y abort, y deja el detalle en un archivo.
 *
 * Correr: node --test extensions/lib/gate.test.ts
 */

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { colaDelArchivo, correrComando, formatearSegundos, lineasDeFalla } from "./gate.ts";

const carpeta = (): string => mkdtempSync(join(tmpdir(), "gate-test-"));

test("el event loop sigue vivo mientras corre la puerta", async () => {
  let ticks = 0;
  const reloj = setInterval(() => ticks++, 50);
  const resultado = await correrComando({ cwd: carpeta(), comando: "sleep 0.6; echo listo" });
  clearInterval(reloj);

  assert.equal(resultado.ok, true);
  assert.match(resultado.resumen, /listo/);
  assert.ok(ticks >= 5, `los timers no corrieron (${ticks} ticks): la puerta bloqueó el proceso`);
});

test("vuelve enseguida aunque el comando deje un hijo vivo", async () => {
  const t0 = Date.now();
  const resultado = await correrComando({ cwd: carpeta(), comando: "sleep 30 & echo ok" });
  const segundos = (Date.now() - t0) / 1000;

  assert.equal(resultado.ok, true);
  assert.ok(segundos < 5, `tardó ${segundos}s: un hijo vivo retuvo la salida`);
});

test("en rojo dice qué falló y guarda el detalle", async () => {
  const dir = carpeta();
  writeFileSync(join(dir, "falla.sh"), "#!/usr/bin/env bash\necho '✓ lo que anda'\necho '✗ verificador 61 en rojo'\nexit 3\n");
  const resultado = await correrComando({ cwd: dir, comando: "bash falla.sh" });

  assert.equal(resultado.ok, false);
  assert.match(resultado.resumen, /verificador 61/);
  assert.match(resultado.mensaje, /qué falló/);
  assert.match(colaDelArchivo(resultado.archivo, 4096), /verificador 61/);
});

test("el timeout corta el comando y lo dice", async () => {
  const t0 = Date.now();
  const resultado = await correrComando({ cwd: carpeta(), comando: "sleep 30", limiteMs: 400 });
  const segundos = (Date.now() - t0) / 1000;

  assert.equal(resultado.ok, false);
  assert.match(resultado.resumen, /colgada/);
  assert.ok(segundos < 5, `el timeout no cortó (${segundos}s)`);
});

test("el abort corta el comando y lo dice", async () => {
  const control = new AbortController();
  setTimeout(() => control.abort(), 250);
  const t0 = Date.now();
  const resultado = await correrComando({
    cwd: carpeta(),
    comando: "sleep 30",
    signal: control.signal,
  });

  assert.equal(resultado.ok, false);
  assert.match(resultado.resumen, /interrumpida/);
  assert.ok((Date.now() - t0) / 1000 < 5, "el abort no cortó");
});

test("el progreso cuenta por dónde va", async () => {
  const vistos: string[] = [];
  const resultado = await correrComando({
    cwd: carpeta(),
    comando: "for paso in alpha beta gamma; do echo \"paso $paso\"; sleep 0.7; done",
    progreso: (linea) => vistos.push(linea),
  });

  assert.equal(resultado.ok, true);
  assert.ok(vistos.length >= 1, "no avisó progreso");
  assert.ok(vistos.some((linea) => /paso (alpha|beta|gamma)/.test(linea)), vistos.join(" | "));
});

test("sigue el registro de la puerta aunque el comando no diga nada por consola", async () => {
  const dir = carpeta();
  const registro = join(dir, "gate.log");
  const previo = process.env.PI_GATE_LOG;
  process.env.PI_GATE_LOG = registro;
  try {
    const vistos: string[] = [];
    // Así escribe la puerta de verdad: el detalle va a $PI_GATE_LOG y a la
    // consola solo le deja el resumen.
    const resultado = await correrComando({
      cwd: dir,
      comando: 'echo "› cargo clippy" >> "$PI_GATE_LOG"; sleep 3; echo "✗ verificador 61" >> "$PI_GATE_LOG"; exit 1',
      progreso: (linea) => vistos.push(linea),
    });

    assert.equal(resultado.ok, false);
    assert.match(resultado.resumen, /verificador 61/);
    assert.match(resultado.mensaje, /verificador 61/);
    assert.equal(resultado.archivo, registro);
    assert.ok(vistos.some((linea) => /clippy/.test(linea)), vistos.join(" | "));
  } finally {
    if (previo === undefined) delete process.env.PI_GATE_LOG;
    else process.env.PI_GATE_LOG = previo;
  }
});

test("las líneas de falla se limpian y se recortan", () => {
  const texto = "\u001b[31m✗ uno\u001b[0m\n  ✓ dos\n\u001b[31m✗ tres\u001b[0m\n";
  const fallas = lineasDeFalla(texto).split("\n");
  assert.deepEqual(fallas, ["✗ uno", "✗ tres"]);
  assert.equal(lineasDeFalla("  ✓ todo bien"), "");
});

test("los segundos se leen como los diría una persona", () => {
  assert.equal(formatearSegundos(9), "9s");
  assert.equal(formatearSegundos(75), "1m 15s");
  assert.equal(formatearSegundos(240), "4m");
});
