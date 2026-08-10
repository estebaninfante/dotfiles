#!/usr/bin/env bash
# Rofi menu: switch power profiles via tuned-ppd.
set -euo pipefail

current=$(power-mode.sh status | awk '{print $NF}')
gpu_status=$(gpu-mode.sh status 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="Modo:") print $(i+1)}' || echo "n/d")
gpu_icon=$( [ "$gpu_status" = "gaming" ] && echo "" || echo "" )

choice=$(printf "  Performance\n  Balanced\n  Power Saver\n  Toggle (invertir)\n────────────────\n${gpu_icon}  GPU-JUGAR (activar NVIDIA)\n$( [ "$gpu_status" = "gaming" ] && echo "  GPU-AHORRAR (suspender)" )" | rofi -dmenu -p "Modo Energia" -mesg "Actual: $current | GPU: $gpu_status")

case "$choice" in
  *Performance*) power-mode.sh performance ;;
  *Balanced*)    power-mode.sh balanced ;;
  *Power*)       power-mode.sh power-saver ;;
  *Toggle*)      power-mode.sh toggle ;;
  *GPU-JUGAR*)   gpu-mode.sh gaming ;;
  *GPU-AHORRAR*) gpu-mode.sh battery ;;
  *)             exit 0 ;;
esac

notify-send -u low "Modo Energia" "$(power-mode.sh status) | $(gpu-mode.sh status 2>/dev/null)"