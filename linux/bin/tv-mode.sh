#!/usr/bin/env bash

# Verifica que el HDMI esté conectado
if ! hyprctl monitors | grep -q "^Monitor HDMI-A-1"; then
    notify-send "Modo TV" "No hay un monitor HDMI conectado."
    exit 1
fi

# Activa el televisor como principal
hyprctl keyword monitor "HDMI-A-1,preferred,0x0,1"

# Desactiva la pantalla del portátil
hyprctl keyword monitor "eDP-1,disable"

# Mueve todos los workspaces al televisor
for i in {1..10}; do
    hyprctl dispatch moveworkspacetomonitor "$i HDMI-A-1"
done

notify-send "Modo TV" "Activado"
