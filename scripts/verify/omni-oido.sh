#!/usr/bin/env bash
# verify/omni-oido.sh — la compuerta del oído abierto: cuándo se despierta,
# cuándo ignora, y que no se dispare con palabras parecidas.
#
# Uso: scripts/verify/omni-oido.sh [--quiet]
set -uo pipefail
exec python3 "$HOME/dotfiles/scripts/verify/omni-oido.py" "$@"
