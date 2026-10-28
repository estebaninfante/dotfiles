#!/usr/bin/env bash
# verify/omni-web.sh — la página local de Omni: levanta, sirve, refleja el
# estado real y rechaza pedidos mal formados. Sin micrófono ni modelo.
#
# Uso: scripts/verify/omni-web.sh [--quiet]
set -uo pipefail
exec python3 "$HOME/dotfiles/scripts/verify/omni-web.py" "$@"
