import { test } from "node:test";
import assert from "node:assert/strict";

import {
  deLaSesion,
  descendientesDe,
  hijosDe,
  indiceMarkdown,
  lineasArbol,
  markdownTraza,
  raicesDe,
  raizDe,
  textoTraza,
  type Tarea,
} from "./trazas.ts";

const t = (
  id: string,
  extra: Partial<Tarea> = {},
): Tarea => ({
  id,
  titulo: `Título ${id}`,
  pedido: `Pedido ${id}`,
  creado: "2026-10-19T03:00:00.000Z",
  actualizado: "2026-10-19T03:00:05.000Z",
  estado: "activa",
  pasos: [],
  ...extra,
});

const sesion = t("T-ROOT", {
  tipo: "sesion",
  agente: "puma",
  dueno: "ses-1",
  session: "/tmp/sesion.jsonl",
});
const pedidoA = t("T-AAA", { padre: "T-ROOT", tipo: "pedido", agente: "puma" });
const pedidoB = t("T-BBB", { padre: "T-ROOT", tipo: "pedido", agente: "puma" });
const delegado = t("T-CCC", {
  padre: "T-AAA",
  tipo: "subtarea",
  agente: "researcher",
});
const items = [sesion, pedidoA, pedidoB, delegado];

test("un ticket raíz es el de la sesión y no tiene padre", () => {
  assert.equal(raizDe(items, delegado).id, "T-ROOT");
  assert.equal(raizDe(items, pedidoA).id, "T-ROOT");
  assert.deepEqual(raicesDe(items).map((x) => x.id), ["T-ROOT"]);
});

test("los hijos salen en orden de creación", () => {
  assert.deepEqual(hijosDe(items, "T-ROOT").map((x) => x.id), ["T-AAA", "T-BBB"]);
  assert.deepEqual(hijosDe(items, "T-AAA").map((x) => x.id), ["T-CCC"]);
});

test("los descendientes recorren todo el subárbol", () => {
  assert.deepEqual(descendientesDe(items, "T-ROOT").map((x) => x.id), [
    "T-AAA",
    "T-CCC",
    "T-BBB",
  ]);
});

test("el árbol muestra raíz y subtickets indentados", () => {
  const lineas = lineasArbol(items, "T-ROOT", Date.parse("2026-10-19T03:01:00.000Z"));
  assert.equal(lineas.length, 4);
  assert.match(lineas[0]!, /^T-ROOT ▶/);
  assert.match(lineas[1]!, /^├─T-AAA/);
  assert.match(lineas[2]!, /^│  └─T-CCC/);
  assert.match(lineas[3]!, /^└─T-BBB/);
});

test("el texto de la traza incluye el subárbol y el resultado de cada paso", () => {
  const conPaso = items.map((x) =>
    x.id === "T-AAA"
      ? {
          ...x,
          pasos: [
            {
              t: "2026-10-19T03:00:01.000Z",
              tipo: "tool" as const,
              nombre: "bash",
              resumen: "$ ls",
              ok: true,
              ms: 12,
              resultado: "archivo.txt",
            },
            {
              t: "2026-10-19T03:00:02.000Z",
              tipo: "respuesta" as const,
              resumen: "Listo: el archivo existe.",
            },
          ],
        }
      : x,
  );
  const texto = textoTraza(pedidoA, conPaso);
  assert.match(texto, /TICKET T-AAA/);
  assert.match(texto, /TICKET T-CCC/);
  assert.match(texto, /bash \$ ls/);
  assert.match(texto, /archivo\.txt/);
  assert.match(texto, /💬 Listo: el archivo existe\./);
});

test("el Markdown de la sesión lista todos los tickets y el agente", () => {
  const md = markdownTraza(sesion, items, {
    ahora: Date.parse("2026-10-19T03:02:00.000Z"),
  });
  assert.match(md, /# Traza T-ROOT · Título T-ROOT/);
  assert.match(md, /- \*\*agente:\*\* puma/);
  assert.match(md, /- \*\*tickets:\*\* 4/);
  assert.match(md, /T-AAA/);
  assert.match(md, /T-CCC/);
  assert.match(md, /## T-ROOT/);
});

test("el índice apunta a un archivo por sesión", () => {
  const md = indiceMarkdown(items, Date.parse("2026-10-19T03:03:00.000Z"));
  assert.match(md, /\[T-ROOT\]\(\.\/T-ROOT\.md\)/);
  assert.match(md, /puma/);
});

test("los tickets se filtran por la sesión dueña", () => {
  assert.deepEqual(
    deLaSesion(items, "ses-1").map((x) => x.id),
    ["T-ROOT", "T-AAA", "T-BBB", "T-CCC"],
  );
  assert.equal(deLaSesion(items, "ses-2").length, 0);
});
