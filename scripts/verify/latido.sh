#!/usr/bin/env bash
# verify/latido.sh — visor de pensamiento y tareas con id/trace.
#
# Solo lee; no cambia nada. Sale 0 si:
#   - los helpers puros de pensamiento.ts pasan sus casos;
#   - el bloque nativo de pensamiento está oculto (no se lee dos veces);
#   - conversar.ts muestra agente × tarea y acelera cuando hay cola;
#   - rig.ts crea tareas con id, guarda trace y expone /tarea, /tareas.
#
# Uso:
#   scripts/verify/latido.sh          # texto
#   scripts/verify/latido.sh --quiet  # solo FAIL/AVISO
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXTS="$REPO/linux/pi/agent/extensions"
HELPERS="$EXTS/lib/pensamiento.ts"
SETTINGS="$REPO/linux/pi/agent/settings.json"
LATIDO="$REPO/linux/config/pi/latido.json"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

# --- 1. helpers puros: se ejecutan solos con Node --------------------------
if out="$(node "$HELPERS" 2>&1)"; then
    if printf '%s\n' "$out" | grep -q '^FALLA'; then
        fail "pensamiento.ts (lib) tiene casos rotos: $(printf '%s' "$out" | grep '^FALLA' | head -1)"
    else
        ok "pensamiento.ts limpia código y descarta fragmentos partidos"
    fi
else
    fail "pensamiento.ts (lib) no se puede ejecutar con Node"
fi

# --- 2. pensamiento en un solo lugar --------------------------------------
if grep -q '"hideThinkingBlock"[[:space:]]*:[[:space:]]*true' "$SETTINGS"; then
    ok "settings: hideThinkingBlock=true (el widget es el único visor en vivo)"
else
    fail "settings sin hideThinkingBlock=true: el pensamiento se vería dos veces"
fi

if grep -q 'rig:tarea' "$EXTS/conversar.ts" && grep -q 'headerLine' "$EXTS/conversar.ts"; then
    ok "conversar: encabezado agente × tarea desde rig:tarea"
else
    fail "conversar no arma el encabezado agente × tarea"
fi

if grep -q 'setTitle' "$EXTS/conversar.ts"; then
    ok "conversar: publica agente × tarea en el título de la ventana"
else
    fail "conversar no publica el título de la ventana"
fi

if grep -q 'ritmoLectura' "$EXTS/conversar.ts" && grep -q 'fastWordMs' "$EXTS/conversar.ts"; then
    ok "conversar: acelera la lectura cuando la cola crece"
else
    fail "conversar no tiene ritmo adaptativo"
fi

# --- 3. tareas con id y trace ---------------------------------------------
for marca in 'tareas.json' 'registerTool' 'name: "tarea"' 'name: "tareas"' \
             'registerCommand("tarea"' 'registerCommand("tareas"' 'rig:tarea'; do
    if grep -q "$marca" "$EXTS/rig.ts"; then
        ok "rig: $marca"
    else
        fail "rig no tiene $marca"
    fi
done

# --- 4. comportamiento de títulos, ids y resumen --------------------------
if node --input-type=module - "$HELPERS" <<'NODE'
import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";

const { tituloDePedido, idTarea, esCodigo, oracionUtil, limpiarPensamiento, resumenEntrada } =
    await import(pathToFileURL(process.argv[2]).href);

assert.equal(
    tituloDePedido("Necesito que el plugin de pi para ver el pensamiento lo mejores."),
    "Plugin de pi para ver el pensamiento lo mejores",
    "título automático",
);
assert.equal(
    tituloDePedido("/tmp/foto.png Necesito que arregles el latido."),
    "Arregles el latido",
    "título sin adjunto ni cortesía",
);
assert.match(idTarea(1792269424000, 0.42), /^T-[0-9A-Z]{6}$/, "id de tarea");
assert.match(idTarea(1792269424001, 0.42), /^T-[0-9A-Z]{6}$/, "id de tarea (otro instante)");
assert.equal(esCodigo("const x = 1;"), true, "oración de código");
assert.equal(esCodigo("La idea es simple y se entiende bien."), false, "oración de prosa");
assert.equal(oracionUtil("Then drops frames while ."), false, "fragmento partido");
assert.equal(oracionUtil("La idea es simple y se entiende bien."), true, "oración entera");
assert.equal(limpiarPensamiento("Hola `const x=1` mundo.").includes("const"), false, "inline code fuera");
assert.match(limpiarPensamiento("```ts\nconst x = 1\n```\nLa idea sigue."), /La idea sigue/, "bloque fuera");
assert.match(resumenEntrada("bash", { command: "ls -la ~/dotfiles" }), /ls -la/, "resumen bash");
assert.match(resumenEntrada("read", { path: "/tmp/a.ts" }), /a\.ts/, "resumen read");
NODE
then
    ok "títulos, ids y resúmenes de tarea"
else
    fail "títulos, ids o resúmenes de tarea"
fi

# --- 5. ritmo por defecto un poco más rápido ------------------------------
if grep -q '"wordMs"[[:space:]]*:[[:space:]]*150' "$LATIDO"; then
    ok "latido: 150 ms por palabra (antes 180)"
else
    fail "latido.json no está en 150 ms por palabra"
fi

[ "$fails" -eq 0 ] || exit 1
[ "$QUIET" = 1 ] || printf '\n  todo ok\n'
exit 0
