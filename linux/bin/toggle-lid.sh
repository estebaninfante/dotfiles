#!/usr/bin/env bash
# Toggle "suspender al cerrar" (F10).
# ON  → suspende al cerrar tapa AÚN EN AC (flag /run/lid-suspend-force)
# OFF → solo suspende al cerrar con batería (default)

FLAG="/run/lid-suspend-force"

if [ -f "$FLAG" ]; then
    # Toggle OFF
    rm -f "$FLAG"
    systemctl --user stop lid-inhibit.timer lid-inhibit.service 2>/dev/null || true
    notify-send "Suspender al cerrar" "DESACTIVADO — solo suspende con batería"
else
    # Toggle ON
    touch "$FLAG"
    systemctl --user start lid-inhibit.service lid-inhibit.timer 2>/dev/null || true
    notify-send "Suspender al cerrar" "ACTIVADO — se suspenderá aunque esté enchufada"
fi
