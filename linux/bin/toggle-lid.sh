#!/bin/bash

if pgrep -f "systemd-inhibit --what=handle-lid-switch sleep infinity" >/dev/null; then
    pkill -f "systemd-inhibit --what=handle-lid-switch sleep infinity"
    notify-send "Modo tapa" "Desactivado"
else
    systemd-inhibit --what=handle-lid-switch sleep infinity &
    notify-send "Modo tapa" "Activado"
fi
