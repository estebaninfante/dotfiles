#!/usr/bin/env bash
# verify/ramas.sh — un worktree por agente, y dos flujos por proyecto.
#
# Solo lee; no cambia nada. Sale 0 si:
#   - worktrees.json parsea y dice el flujo de cada proyecto (main/developing/directo);
#   - los helpers puros de lib/ramas.ts pasan sus casos con Node;
#   - la extensión quedó instalada (symlink) y registra candado, tool y comando;
#   - `rig work new` saca la base de la misma config.
#
# El camino completo (abrir worktree, escribir, commitear, mergear) se prueba a
# mano con un repo de juguete: `pi --tools read,write,bash,worktree` dos veces,
# una pidiendo escribir en la copia principal (debe bloquear) y otra normal.
#
# Uso:
#   scripts/verify/ramas.sh          # texto
#   scripts/verify/ramas.sh --quiet  # solo FAIL/AVISO
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXTS="$REPO/linux/pi/agent/extensions"
LIB="$EXTS/lib/ramas.ts"
CONFIG="$REPO/linux/pi/agent/worktrees.json"
RIG="$REPO/linux/bin/rig"
PI_HOME="${HOME}/.pi/agent"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

# --- 1. la config: flujos por proyecto ------------------------------------
if ! jq -e . "$CONFIG" >/dev/null 2>&1; then
    fail "worktrees.json no parsea"
else
    ok "worktrees.json parsea"
    esperado=$(
        jq -r '
          [ (.repos.foldertinder.flujo + ":" + .repos.foldertinder.rama),
            (.repos.zentr0.flujo + ":" + .repos.zentr0.rama),
            (.repos.dotfiles.flujo),
            .flujoPorDefecto ]
          | join(" ")' "$CONFIG"
    )
    [ "$esperado" = "main:master developing:dev directo main" ] \
        && ok "flujos: foldertinder main/master, zentr0 developing/dev, dotfiles directo, default main" \
        || fail "flujos inesperados: $esperado"
fi

# --- 2. helpers puros ------------------------------------------------------
if out="$(cd "$EXTS/lib" && node --test ramas.test.ts 2>&1)"; then
    ok "ramas.ts: $(printf '%s' "$out" | grep -c '^✔') casos verdes"
else
    fail "ramas.ts tiene casos rotos: $(printf '%s' "$out" | grep -E '^✖' | head -2 | tr '\n' ' ')"
fi

# --- 3. instalación: symlinks, no copias ----------------------------------
for par in "worktrees.json:$PI_HOME/worktrees.json" "extensions/worktrees.ts:$PI_HOME/extensions/worktrees.ts"; do
    origen="${par%%:*}"; destino="${par##*:}"
    if [ -L "$destino" ] && [ "$(readlink -f "$destino")" = "$REPO/linux/pi/agent/$origen" ]; then
        ok "instalado: $origen"
    else
        fail "$destino no es un symlink al repo"
    fi
done

# --- 4. la extensión hace las cuatro cosas --------------------------------
marca() {
    if grep -q "$1" "$EXTS/worktrees.ts"; then ok "worktrees.ts: $2"; else fail "worktrees.ts no tiene $2"; fi
}
marca 'sections.worktrees' "reglas en el system prompt de cada turno"
marca 'event.toolName === "write" || event.toolName === "edit"' "candado de write/edit"
marca 'event.toolName === "bash"' "candado de bash"
marca 'datos.esWorktree' "dentro de un worktree no bloquea (ahí se trabaja)"
marca 'prepararSubagentes' "un worktree por subagente"
marca 'name: "worktree"' "tool worktree (abrir/lista/cerrar)"
marca 'registerCommand("worktrees"' "comando /worktrees"

# El escape hatch tiene que existir: sin él, el candado es una jaula.
grep -q 'PI_SIN_WORKTREES' "$EXTS/worktrees.ts" \
    && ok "escape hatch: PI_SIN_WORKTREES / /worktrees libre" \
    || fail "no hay forma de desactivar el candado"

grep -q 'PI_RAMAS' "$EXTS/worktrees.ts" && grep -q 'PI_RAMAS' "$RIG" \
    && ok "pi y rig leen la misma config (PI_RAMAS)" \
    || fail "pi y rig no comparten la ruta de la config"

# --- 5. rig saca la base de la config -------------------------------------
if ! bash -n "$RIG" 2>/dev/null; then
    fail "rig no parsea"
else
    ok "rig parsea"
    # Se evalúa solo la función, sin arrancar rig entero.
    base_de() {
        bash -s "$RIG" "$1" <<'BASH'
repo_base_config() { :; }
. <(sed -n '/^repo_base_config()/,/^}/p' "$1")
repo_base_config "$2"
BASH
    }
    [ "$(base_de /tmp/zentr0)" = "dev" ] && ok "rig: repo developing -> base dev" \
        || fail "rig no toma la base developing (dio '$(base_de /tmp/zentr0)')"
    [ "$(base_de /tmp/foldertinder)" = "master" ] && ok "rig: repo main -> base master" \
        || fail "rig no toma la base main (dio '$(base_de /tmp/foldertinder)')"
    [ -z "$(base_de /tmp/dotfiles)" ] && ok "rig: repo directo -> sin base forzada" \
        || fail "rig fuerza base en un repo directo"
fi

[ "$fails" -eq 0 ] || exit 1
[ "$QUIET" = 1 ] || printf '\n  todo ok\n'
exit 0
