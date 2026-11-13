#!/usr/bin/env bash
# verify/ideas.sh — el estándar de ideas está publicado y la captura funciona.
#
# Comprueba, sin criterio humano:
#   1. Existe la regla canónica `linux/agents/estandar-ideas.md`, manda capturar
#      con `machine idea --title` y NO manda escribir en el vault `~/alicia`.
#   2. Las tres entradas que leen las IAs resuelven a esa misma regla:
#        ~/.omp/agent/AGENTS.md        (OMP)
#        ~/.claude/CLAUDE.md           (Claude Code)
#        ~/.config/opencode/AGENTS.md  (OpenCode; dentro del repo symlinkeado)
#   3. En una base temporal: `machine idea --title` crea la idea con nombre y
#      `machine ls --json` la lista como `kind=idea`. No toca la base real.
#
# Uso:
#   scripts/verify/ideas.sh           # texto
#   scripts/verify/ideas.sh --quiet   # solo FALLA/AVISO
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGLA="$REPO/linux/agents/estandar-ideas.md"
DESTINOS=(
    "$HOME/.omp/agent/AGENTS.md"
    "$HOME/.claude/CLAUDE.md"
    "$HOME/.config/opencode/AGENTS.md"
)

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

# --- 1. regla canónica -----------------------------------------------------
if [ -f "$REGLA" ]; then
    ok "existe $REGLA"
    grep -q 'machine idea --title' "$REGLA" \
        && ok "la regla manda capturar con 'machine idea --title'" \
        || fail "la regla no menciona 'machine idea --title'"
    if grep -q 'alicia nuevo' "$REGLA"; then
        fail "la regla todavía manda escribir en el vault (~/alicia nuevo)"
    else
        ok "la regla no manda escribir en ~/alicia (vault congelado)"
    fi
else
    fail "falta $REGLA"
fi

# --- 2. las tres IAs leen la misma regla -----------------------------------
# OMP tiene reglas propias (escritorio headless) y suma el estándar con un
# `@import`; Claude y OpenCode son symlinks directos a la regla canónica.
if [ -f "$HOME/.omp/agent/AGENTS.md" ] \
    && grep -q '@.*estandar-ideas\.md' "$HOME/.omp/agent/AGENTS.md"; then
    ok "~/.omp/agent/AGENTS.md importa la regla canónica"
else
    fail "~/.omp/agent/AGENTS.md no importa la regla canónica"
fi

for dst in "${DESTINOS[@]}"; do
    [ "$dst" = "$HOME/.omp/agent/AGENTS.md" ] && continue
    if [ -e "$dst" ]; then
        real="$(readlink -f "$dst")"
        if [ "$real" = "$(readlink -f "$REGLA")" ]; then
            ok "$dst → regla canónica"
        else
            fail "$dst apunta a $real, no a la regla canónica"
        fi
    else
        fail "no existe $dst (corré scripts/link-dotfiles.sh)"
    fi
done

# --- 3. captura de punta a punta en una base temporal ----------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if command -v machine >/dev/null 2>&1; then
    export MACHINE_DB="$TMP/machine.db"
    if machine init >/dev/null 2>&1 \
        && machine idea --title "Prueba de captura" "texto de prueba" >/dev/null 2>&1 \
        && machine ls --json 2>/dev/null | grep -q '"kind": "idea"'; then
        ok "machine idea --title crea la idea y machine ls la lista"
    else
        fail "machine idea no dejó la idea en la base temporal"
    fi
    if machine idea --title "Segunda" "otra" >/dev/null 2>&1 \
        && machine ls --json 2>/dev/null | grep -q 'Segunda'; then
        ok "el nombre corto sobrevive a la captura"
    else
        fail "el nombre corto no aparece en machine ls"
    fi
else
    fail "falta el CLI 'machine' en PATH"
fi

if [ "$fails" -eq 0 ]; then
    [ "$QUIET" = 1 ] || printf '\nideas: OK\n'
    exit 0
fi
exit 1
