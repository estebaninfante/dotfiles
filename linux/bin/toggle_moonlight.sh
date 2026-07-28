#!/bin/bash

# Usar el socket de la instancia activa de Hyprland
# hyprctl usa automáticamente $HYPRLAND_INSTANCE_SIGNATURE si está presente
# en el entorno del proceso que lo llama.

STATE_FILE="/tmp/moonlight_toggle"

if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
    hyprctl keyword input:kb_options "caps:super" > /dev/null 2>&1
    hyprctl dispatch workspace previous > /dev/null 2>&1
    hyprctl dispatch submap reset > /dev/null 2>&1
else
    touch "$STATE_FILE"
    hyprctl keyword input:kb_options "" > /dev/null 2>&1
    hyprctl dispatch workspace 10 > /dev/null 2>&1
    hyprctl dispatch submap passthrough > /dev/null 2>&1
fi
