#!/usr/bin/env bash
# verify/omni-buzon.sh — el buzón hablado de Omni: un agente avisa, Omni lo dice.
#
# Sin audio y sin red: comprueba nombre, texto literal, urgencia, que junte los
# pendientes en una frase, que no repita lo escuchado y que no llame a un modelo.
#
# Uso: scripts/verify/omni-buzon.sh [--quiet]
set -uo pipefail
exec python3 "$HOME/dotfiles/scripts/verify/omni-buzon.py" "$@"
