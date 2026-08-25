#!/usr/bin/env bash

legacy_inhibitor='systemd-inhibit --what=handle-lid-switch sleep infinity'

if systemctl --user is-active --quiet lid-inhibit.service || pgrep -f "$legacy_inhibitor" >/dev/null; then
    systemctl --user stop lid-inhibit.timer lid-inhibit.service
    pkill -f "$legacy_inhibitor" 2>/dev/null || true
    notify-send "Suspender al cerrar" "Activado"
else
    systemctl --user start lid-inhibit.service lid-inhibit.timer
    notify-send "Suspender al cerrar" "Desactivado; suspensión automática en 30 min"
fi
