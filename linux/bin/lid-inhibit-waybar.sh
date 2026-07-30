#!/bin/bash

# Waybar custom module: lid inhibit status

update() {
    if pgrep -f "systemd-inhibit --what=handle-lid-switch sleep infinity" >/dev/null; then
        echo '{"text":"S", "tooltip":"Suspender al cerrar: Desactivado (inhibido)", "class":"inhibited"}'
    else
        echo '{"text":"S", "tooltip":"Suspender al cerrar: Activado", "class":"active"}'
    fi
}

update

while true; do
    sleep 2
    update
done
