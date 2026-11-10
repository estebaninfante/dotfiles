#!/usr/bin/env bash
# verify/ideas.sh — el estándar de ideas está publicado y la captura funciona.
#
# Comprueba, sin criterio humano:
#   1. Existe la regla canónica `linux/agents/estandar-ideas.md` y nombra los
#      comandos de captura (`idea raw`) y de consulta (`alicia next`).
#   2. Las tres entradas que leen las IAs resuelven a esa misma regla:
#        ~/.omp/agent/AGENTS.md        (OMP)
#        ~/.claude/CLAUDE.md           (Claude Code)
#        ~/.config/opencode/AGENTS.md  (OpenCode; dentro del repo symlinkeado)
#   3. En un vault temporal: `idea raw` crea un pendiente y `alicia next` lo
#      lista como accionable. No toca las ideas reales del usuario.
#   4. `alicia check` valida el grafo temporal.
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
    grep -q 'idea raw' "$REGLA" && ok "la regla manda capturar con 'idea raw'" \
        || fail "la regla no menciona 'idea raw'"
    grep -q 'alicia next' "$REGLA" && ok "la regla manda consultar con 'alicia next'" \
        || fail "la regla no menciona 'alicia next'"
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

# --- 3. captura de punta a punta en vault temporal -------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if command -v idea >/dev/null 2>&1 && command -v alicia >/dev/null 2>&1; then
    nota="$(ALICIA_VAULT="$TMP" idea raw "prueba de captura del estándar" 2>&1)"
    if [ -f "$nota" ]; then
        ok "idea raw crea el pendiente"
    else
        fail "idea raw no creó la nota: $nota"
    fi
    if ALICIA_VAULT="$TMP" alicia --vault "$TMP" next --json 2>/dev/null \
        | grep -q "prueba-de-captura"; then
        ok "alicia next lista el pendiente como accionable"
    else
        fail "alicia next no lista el pendiente"
    fi
    if ALICIA_VAULT="$TMP" alicia --vault "$TMP" check >/dev/null 2>&1; then
        ok "alicia check valida el grafo"
    else
        fail "alicia check falla en el vault temporal"
    fi
else
    fail "faltan los CLI 'idea' y/o 'alicia' en PATH"
fi

if [ "$fails" -eq 0 ]; then
    [ "$QUIET" = 1 ] || printf '\nideas: OK\n'
    exit 0
fi
printf '\nideas: %s falla(s)\n' "$fails"
exit 1
