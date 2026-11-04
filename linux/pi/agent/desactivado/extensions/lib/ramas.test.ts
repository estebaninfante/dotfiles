import { test } from "node:test";
import assert from "node:assert/strict";

import {
  comandoMutaRepo,
  configNormalizada,
  dentroDe,
  idCorto,
  mutacionDetectada,
  normalizar,
  politicaDe,
  ramaDe,
  rutaWorktree,
  rutasEscritas,
  slug,
} from "./ramas.ts";

const config = configNormalizada({
  flujoPorDefecto: "main",
  prefijoRama: "agente",
  repos: {
    foldertinder: { flujo: "main", rama: "master" },
    zentr0: { flujo: "developing", rama: "dev" },
    otro: { flujo: "developing" },
    dotfiles: { flujo: "directo" },
  },
});

test("un repo con rama fija usa esa rama como base", () => {
  const p = politicaDe(config, "foldertinder");
  assert.deepEqual(p, { repo: "foldertinder", flujo: "main", base: "master", exigeWorktree: true });
});

test("un repo developing sin rama configurada usa una rama developing", () => {
  assert.equal(politicaDe(config, "otro").base, "developing");
  assert.equal(politicaDe(config, "zentr0").base, "dev");
});

test("un repo sin configurar cae en el flujo por defecto, sobre la rama principal", () => {
  const p = politicaDe(config, "speeedy");
  assert.equal(p.flujo, "main");
  assert.equal(p.base, null);
  assert.equal(p.exigeWorktree, true);
});

test("el flujo directo no pide worktree ni rama base", () => {
  const p = politicaDe(config, "dotfiles");
  assert.equal(p.exigeWorktree, false);
  assert.equal(p.base, null);
});

test("una config rota no rompe: cae en main y prefijo agente", () => {
  const rota = configNormalizada({ flujoPorDefecto: "qualquiera", repos: { x: { flujo: "nada" } } });
  assert.equal(rota.flujoPorDefecto, "main");
  assert.equal(rota.prefijoRama, "agente");
  assert.equal(politicaDe(rota, "x").flujo, "main");
});

test("slug limpia acentos, espacios y signos", () => {
  assert.equal(slug("Menú de Sonido: TODOS los videos!"), "menu-de-sonido-todos-los-videos");
  assert.equal(slug("   "), "trabajo");
  assert.equal(slug("a".repeat(80)).length, 40);
});

test("la rama de trabajo lleva el prefijo configurado", () => {
  assert.equal(ramaDe(config, "Sonido Menu"), "agente/sonido-menu");
});

test("el id de un subagente sale de las primeras palabras de la tarea", () => {
  assert.equal(
    idCorto("Listá los archivos del directorio actual (incluidos los ocultos) y devolvé la lista"),
    "lista-los-archivos-del",
  );
  assert.equal(idCorto(""), "trabajo");
});

test("el worktree va al lado del repo, en .rig-worktrees", () => {
  assert.equal(
    rutaWorktree("/home/eztvn/developing/foldertinder", "sonido"),
    "/home/eztvn/developing/.rig-worktrees/foldertinder/sonido",
  );
});

test("normalizar resuelve ~ y ..", () => {
  assert.equal(normalizar("~/x/../y", "/tmp", "/home/u"), "/home/u/y");
  assert.equal(normalizar("sub/archivo", "/repo"), "/repo/sub/archivo");
});

test("dentroDe no confunde /repo con /repo2", () => {
  assert.ok(dentroDe("/repo", "/repo/a/b"));
  assert.ok(dentroDe("/repo", "/repo"));
  assert.ok(!dentroDe("/repo", "/repo2/a"));
});

test("lecturas de git no cuentan como escritura", () => {
  assert.equal(mutacionDetectada("git status --short"), null);
  assert.equal(mutacionDetectada("git log --oneline -3"), null);
  assert.equal(mutacionDetectada("git diff --stat"), null);
  assert.equal(mutacionDetectada("sed -n 1,40p archivo.py"), null);
  assert.equal(mutacionDetectada("ls -la 2>&1"), null);
  assert.equal(mutacionDetectada("node --test static/js/lib/*.test.mjs 2>&1 | tail -5"), null);
  assert.equal(mutacionDetectada("echo hola > /dev/null"), null);
});

test("lo que escribe en el repo se detecta con motivo", () => {
  assert.match(String(mutacionDetectada("git commit -am 'x'")), /git/);
  assert.match(String(mutacionDetectada("git checkout -b nueva")), /git/);
  assert.match(String(mutacionDetectada("npm install")), /dependencias/);
  assert.match(String(mutacionDetectada("sed -i s/a/b/ archivo")), /sed/);
  assert.match(String(mutacionDetectada("echo hola > salida.txt")), /redirección/);
  assert.match(String(mutacionDetectada("mkdir -p build")), /archivos/);
});

test("un comando que trabaja en otro lado no se bloquea", () => {
  const repo = "/home/u/developing/foldertinder";
  assert.equal(
    comandoMutaRepo("cd /home/u/dotfiles && sed -i s/a/b/ archivo", {
      repo,
      cwd: "/home/u",
      home: "/home/u",
    }),
    null,
  );
  assert.equal(comandoMutaRepo("date > /tmp/marca.txt", { repo, cwd: repo, home: "/home/u" }), null);
});

test("un comando que trabaja en la copia principal se bloquea", () => {
  const repo = "/home/u/developing/foldertinder";
  assert.match(
    String(comandoMutaRepo("git commit -am wip", { repo, cwd: repo, home: "/home/u" })),
    /git/,
  );
  assert.match(
    String(comandoMutaRepo(`sed -i s/a/b/ ${repo}/ft/server.py`, { repo, cwd: "/home/u", home: "/home/u" })),
    /sed/,
  );
  assert.match(
    String(comandoMutaRepo("python3 -c 'print(1)' > static/index.html", { repo, cwd: repo })),
    /redirección/,
  );
});

test("las rutas que escribe un comando salen a la vista", () => {
  assert.deepEqual(rutasEscritas("echo hola > /tmp/wt2/afuera.txt"), ["/tmp/wt2/afuera.txt"]);
  assert.deepEqual(rutasEscritas("ls -la 2>&1"), []);
  assert.deepEqual(rutasEscritas("git commit -am wip"), []);
  assert.deepEqual(rutasEscritas("sed -i s/a/b/ ft/server.py"), ["ft/server.py"]);
  assert.deepEqual(rutasEscritas("cp a.txt b.txt"), ["b.txt"]);
  assert.deepEqual(rutasEscritas("rm -rf build tmp"), ["build", "tmp"]);
  assert.deepEqual(rutasEscritas("cat x | tee /tmp/registro.log"), ["/tmp/registro.log"]);
});
