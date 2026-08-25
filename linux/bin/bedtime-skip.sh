#!/usr/bin/env bash
# Cancela el apagado de las 21:00 de HOY (flag /run/bedtime-skip).
# Funciona antes y durante los 5 min de gracia. Muere al reboot:
# manana el apagado automatico vuelve a funcionar.
set -euo pipefail

date +%F | sudo tee /run/bedtime-skip >/dev/null
echo "Apagado de las 21:00 cancelado para hoy ($(cat /run/bedtime-skip))."
