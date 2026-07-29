#!/usr/bin/env bash
set -euo pipefail

LAPTOP="eDP-1"
TV="HDMI-A-1"

LAPTOP_SINK=59
HDMI_SINK=75

MODE="${1:-toggle}"

restore_laptop() {
    hyprctl keyword monitor "$LAPTOP,preferred,auto,2" >/dev/null 2>&1 || true
}

trap restore_laptop ERR

# ¿Está conectado el televisor?
if ! hyprctl monitors | grep -q "^Monitor $TV"; then
    exit 0
fi

is_tv_mode() {
    hyprctl monitors all | awk -v mon="$LAPTOP" '
        $1=="Monitor" && $2==mon {f=1; next}
        f && /disabled:/ {
            if ($2=="true") exit 0
            exit 1
        }
    '
}

switch_audio() {
    wpctl set-default "$1" >/dev/null 2>&1 || true
}

# Si se ejecuta automáticamente y ya estamos en modo TV, salir.
if [[ "$MODE" == "auto" ]] && is_tv_mode; then
    exit 0
fi

# ==========================
# MODO PORTÁTIL
# ==========================
if [[ "$MODE" == "toggle" ]] && is_tv_mode; then

    hyprctl keyword monitor "$LAPTOP,preferred,auto,2"
    sleep 0.2

    hyprctl keyword monitor "$TV,preferred,auto,1"

    for i in $(seq 1 10); do
        hyprctl dispatch moveworkspacetomonitor "$i $LAPTOP" >/dev/null 2>&1 || true
    done

    switch_audio "$LAPTOP_SINK"

    notify-send \
        -a "Hyprland" \
        -i video-display \
        -t 2500 \
        "💻 Modo portátil" \
        "Pantalla y audio restaurados."

    exit 0
fi

# ==========================
# MODO TV
# ==========================

hyprctl keyword monitor "$TV,preferred,auto,1"
sleep 0.3

for i in $(seq 1 10); do
    hyprctl dispatch moveworkspacetomonitor "$i $TV" >/dev/null 2>&1 || true
done

sleep 0.1

hyprctl keyword monitor "$LAPTOP,disable"

switch_audio "$HDMI_SINK"

if [[ "$MODE" == "auto" ]]; then
    notify-send \
        -a "Hyprland" \
        -i video-display \
        -t 3500 \
        "📺 Modo TV" \
        "Televisor detectado.\nPantalla y audio activados automáticamente."
else
    notify-send \
        -a "Hyprland" \
        -i video-display \
        -t 2500 \
        "📺 Modo TV" \
        "Pantalla y audio cambiados al televisor."
fi
