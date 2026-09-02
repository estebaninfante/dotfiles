#!/usr/bin/env bash

# Waybar custom module: lid inhibit status

FLAG="/run/lid-suspend-force"

update() {
    if [ -f "$FLAG" ]; then
        echo '{"text":"S", "tooltip":"Suspender al cerrar: ACTIVADO (enchufada también)", "class":"active"}'
    else
        echo '{"text":"S", "tooltip":"Suspender al cerrar: DESACTIVADO (solo batería)", "class":"inhibited"}'
    fi
}

update

while true; do
    sleep 2
    update
done
