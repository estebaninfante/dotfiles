#!/usr/bin/env bash
# verify/omni-voz.sh — un solo modelo para oído y boca: Omni pide la voz al
# modelo local, reproduce ese WAV, y transcribe mandándole el audio al mismo
# modelo. Sin audio real, sin red y sin nube.
#
# Uso: scripts/verify/omni-voz.sh [--quiet]
set -uo pipefail
exec python3 "$HOME/dotfiles/scripts/verify/omni-voz.py" "$@"
