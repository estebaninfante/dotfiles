#!/usr/bin/env bash
# verify/conserje-estado.sh — corte #1 del conserje: contar cómo van los agentes
# con procedencia, sin modelo, sin audio y sin tocar las trazas reales.
#
# Comprueba: ruta correcta, cada afirmación con fuente existente, lo viejo se
# dice "sin confirmar", no llama a ningún modelo, deja registro del pedido, y
# cuando no hay datos lo dice en vez de inventar.
#
# Uso: scripts/verify/conserje-estado.sh [--quiet]
set -uo pipefail
exec python3 "$HOME/dotfiles/scripts/verify/conserje-estado.py" "$@"
