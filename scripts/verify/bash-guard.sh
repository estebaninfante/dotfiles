#!/usr/bin/env bash
# verify/bash-guard.sh — python3 dentro de bash no puede escribir archivos.
#
# El plugin `linux/dsh/plugins/bash-guard` registra un guard global del tool
# `bash`: si el comando invoca python y escribe (open con w/a/x, write_text,
# shutil, os.remove, json.dump…), el harness lo rechaza antes de ejecutarlo.
#
# Corre sin servidor: carga el plugin y prueba comandos permitidos y prohibidos.
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
    echo "FALLA falta node en PATH"
    exit 1
fi

out="$(node "$HERE/bash-guard.mjs" 2>&1)"
if [ "$?" -ne 0 ]; then
    printf '%s\n' "$out"
    echo "FALLA el candado no distingue lectura de escritura"
    exit 1
fi

[ "$QUIET" = 1 ] || printf '  ok    %s\n' "$out"
[ "$QUIET" = 1 ] || printf '\nbash-guard: OK\n'
exit 0
