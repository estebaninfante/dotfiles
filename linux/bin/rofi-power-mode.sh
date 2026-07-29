#!/usr/bin/env bash
# Rofi menu: switch power profiles via tuned-ppd.
set -euo pipefail

current=$(power-mode.sh status | awk '{print $NF}')

choice=$(printf "  Performance\n  Balanced\n  Power Saver\n  Toggle (invertir)" | rofi -dmenu -p "Modo Energia" -mesg "Actual: $current")

case "$choice" in
  *Performance*) power-mode.sh performance ;;
  *Balanced*)    power-mode.sh balanced ;;
  *Power*)       power-mode.sh power-saver ;;
  *Toggle*)      power-mode.sh toggle ;;
  *)             exit 0 ;;
esac

notify-send -u low "Modo Energia" "$(power-mode.sh status)"