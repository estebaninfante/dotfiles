import { test } from "node:test";
import assert from "node:assert/strict";

import { instalarEscudo } from "./escudo.ts";

function falso() {
  const manejadores = new Map<string, (motivo: unknown) => void>();
  return {
    proceso: { on: (evento: string, m: (motivo: unknown) => void) => manejadores.set(evento, m) },
    disparar: (evento: string, motivo: unknown) => manejadores.get(evento)?.(motivo),
    tiene: (evento: string) => manejadores.has(evento),
  };
}

test("se engancha a excepciones y a promesas rechazadas", () => {
  const f = falso();
  instalarEscudo(f.proceso, () => {});
  assert.ok(f.tiene("uncaughtException"));
  assert.ok(f.tiene("unhandledRejection"));
});

test("anota el motivo con su hora, sin tirar", () => {
  const f = falso();
  const lineas: string[] = [];
  instalarEscudo(f.proceso, (l) => lineas.push(l), () => "2026-10-21T12:00:00.000Z");
  f.disparar("uncaughtException", new Error("ENOENT: voice"));
  f.disparar("unhandledRejection", "algo raro");
  assert.equal(lineas.length, 2);
  assert.match(lineas[0], /2026-10-21T12:00:00\.000Z/);
  assert.match(lineas[0], /ENOENT: voice/);
  assert.match(lineas[1], /algo raro/);
});
