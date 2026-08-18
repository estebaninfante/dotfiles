#!/usr/bin/env bash

# Usar el socket de la instancia activa de Hyprland
# hyprctl usa automáticamente $HYPRLAND_INSTANCE_SIGNATURE si está presente
# en el entorno del proceso que lo llama.
#
# NOTA: Hyprland >= 0.50 con config en Lua requiere `hyprctl eval`,
# `hyprctl keyword` y `hyprctl dispatch` legacy ya no funcionan.

STATE_FILE="/tmp/moonlight_toggle"

set_kb_options() {
    hyprctl eval "hl.config({ input = { kb_options = \"$1\" } })" > /dev/null 2>&1
}

switch_workspace() {
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"$1\" }))" > /dev/null 2>&1
}

switch_submap() {
    hyprctl eval "hl.dispatch(hl.dsp.submap(\"$1\"))" > /dev/null 2>&1
}

if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
    set_kb_options "caps:super"
    switch_workspace "previous"
    switch_submap "reset"
else
    touch "$STATE_FILE"
    set_kb_options ""
    switch_workspace "10"
    switch_submap "passthrough"
fi
