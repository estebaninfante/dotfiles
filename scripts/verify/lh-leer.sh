#!/usr/bin/env bash
# verify/lh-leer.sh — el puente que lee en voz alta lo que responde el tutor de
# LearnHarness.
#
# Arma chats de mentira, corre el vigía en seco (sin audio, sin tocar la app) y
# comprueba: no lee el historial al arrancar, lee el mensaje nuevo limpio, no
# repite, ignora turnos sin texto y respeta el interruptor `leer`.
#
# Uso: scripts/verify/lh-leer.sh [--quiet]
set -uo pipefail
exec python3 "$HOME/dotfiles/scripts/verify/lh-leer.py" "$@"
