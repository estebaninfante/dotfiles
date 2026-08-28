#!/usr/bin/env bash
# Aplica perfil agresivo solo mientras laptop funciona con batería.
set -euo pipefail

on_battery() {
  for p in /sys/class/power_supply/AC*/online; do
    [ -f "$p" ] && [ "$(cat "$p")" = "1" ] && return 1
  done
  return 0
}

# Syncthing: OFF en batería (ahorro), ON en AC. Respeta apagado manual
# (/tmp/syncthing-manual-off, escrito por el toggle de quickshell; muere
# al reboot — el guard re-aplica por fuente de energía en el próximo boot).
# syncthing corre como unit de SISTEMA (services.syncthing), no user.
sync_ctl() { # $1 = start|stop
  systemctl "$1" syncthing.service
}

if on_battery; then
  /home/eztvn/dotfiles/linux/bin/power-mode.sh power-saver
  /home/eztvn/dotfiles/linux/bin/gpu-mode.sh battery
  sync_ctl stop
else
  [ -f /tmp/syncthing-manual-off ] || sync_ctl start
fi
