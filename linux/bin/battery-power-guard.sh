#!/usr/bin/env bash
# Aplica perfil agresivo solo mientras laptop funciona con batería.
set -euo pipefail

on_battery() {
  for p in /sys/class/power_supply/AC*/online; do
    [ -f "$p" ] && [ "$(cat "$p")" = "1" ] && return 1
  done
  return 0
}

if on_battery; then
  /home/eztvn/dotfiles/linux/bin/power-mode.sh power-saver
  /home/eztvn/dotfiles/linux/bin/gpu-mode.sh battery
fi
