#!/usr/bin/env bash

if pgrep -f "systemd-inhibit --what=handle-lid-switch sleep infinity" >/dev/null; then
    pkill -f "systemd-inhibit --what=handle-lid-switch sleep infinity"
    notify-send "Suspender al cerrar" "Activado"
else
    systemd-inhibit --what=handle-lid-switch sleep infinity &
    notify-send "Suspender al cerrar" "Desactivado"
fi
