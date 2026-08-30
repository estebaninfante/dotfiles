#!/usr/bin/env bash
# Vigila conexion de gamepads (por BT/USB) y entra/sale de modo juego.
#
# Deteccion generica: cualquier device evdev con BTN_GAMEPAD (bit 0x130,
# `k130` en modalias). Cubre el Wii Pro Controller, Xbox, DualSense, etc.
# sin hardcodear nombres.
#
# Transiciones (con debounce para el sleep/reconexion BT):
#   ausente -> presente  : game-mode.sh (entrar) + autoload mapper
#   presente -> ausente  : game-mode.sh exit (salir)
#
# No dispara en el arranque si el pad ya esta conectado (evita sorprender
# en login): solo reacciona a cambios posteriores. Corre como user systemd
# service (graphical-session.target).
set -euo pipefail

DEV_PRESET="desktop"

gamepad_present() {
    local m
    for m in /sys/class/input/input*/modalias; do
        [ -f "$m" ] || continue
        grep -q 'k130' "$m" 2>/dev/null && return 0
    done
    return 1
}

hypr_running() {
    hyprctl version >/dev/null 2>&1
}

reload_mapper() {
    # Recarga el preset autoload del pad (config.json: autoload desktop).
    # Fallo silencioso: el daemon puede no estar gestionando el pad aun.
    input-remapper-control --command autoload >/dev/null 2>&1 || true
}

apply() {
    # $1 = on|off
    case "$1" in
        on)
            reload_mapper
            hypr_running && ~/.local/bin/game-mode.sh
            ;;
        off)
            hypr_running && ~/.local/bin/game-mode.sh exit
            ;;
    esac
}

prev=unknown; cand=unknown; count=0
THRESH=6   # ~6s de estado estable para confirmar transicion

if gamepad_present; then prev=on; else prev=off; fi

while true; do
    cur=off
    gamepad_present && cur=on

    if [ "$cur" != "$prev" ]; then
        if [ "$cur" = "$cand" ]; then
            count=$((count + 1))
            if [ "$count" -ge "$THRESH" ]; then
                apply "$cur"
                prev="$cur"; cand=unknown; count=0
            fi
        else
            cand="$cur"; count=1
        fi
    else
        cand=unknown; count=0
    fi

    sleep 1
done