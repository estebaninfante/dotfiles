#!/usr/bin/env bash
# verify/leer-respuesta.sh — la extensión `leer` dice la respuesta COMPLETA y
# calla cuando corresponde.
#
# Arma un `pi` de mentira (solo los eventos), dispara una corrida y mira lo que
# la extensión habría dicho, sin audio y sin micrófono.
#
# Sale 0 si:
#   - una corrida normal deja la respuesta entera, limpia para el oído;
#   - anuncia por el bus `voz:hablado` (así el cierre de tts-summary no repite);
#   - una corrida cortada por el usuario no dice nada;
#   - con `leer off` no dice nada;
#   - un subagente no dice nada.
#
# Uso: scripts/verify/leer-respuesta.sh [--quiet]
set -uo pipefail
exec node "$HOME/dotfiles/scripts/verify/leer-respuesta.mjs" "$@"
