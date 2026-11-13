#!/usr/bin/env bash
# verify/machine-panel.sh — el panel de proyectos sigue renderizando y sus
# botones de conversación crean la sesión, mandan el contexto y navegan al chat.
#
# Corre sin navegador ni servidor: un React falso con hooks con estado, un
# `fetch` de mentira y un `ctx` mínimo (ver machine-panel.mjs).
#
# Uso:
#   scripts/verify/machine-panel.sh           # texto
#   scripts/verify/machine-panel.sh --quiet   # solo el veredicto
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "FALLA falta node en PATH"
    exit 1
fi

out="$(node "$HERE/machine-panel.mjs" 2>&1)"
if [ "$?" -ne 0 ]; then
    printf '%s\n' "$out"
    echo "FALLA el panel no renderiza o los botones no abren la conversación"
    exit 1
fi

[ "$QUIET" = 1 ] || printf '  ok    %s\n' "$(printf '%s' "$out" | head -1)"
[ "$QUIET" = 1 ] || printf '\nmachine-panel: OK\n'
exit 0
