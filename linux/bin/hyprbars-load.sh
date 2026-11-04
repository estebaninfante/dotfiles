#!/usr/bin/env bash
# hyprbars-load.sh — carga hyprbars (barra de título arriba de cada ventana).
#
# Fuera de proceso a propósito: llamar hl.plugin.load() desde la config Lua
# reentra el parser de Hyprland (load -> reload -> parse -> load ...) y la pila
# se desborda antes de que la sesión termine de arrancar (ver plugins/hyprexpo.lua).
# Idempotente: si ya está cargado no hace nada.
set -uo pipefail

USER_NAME="${USER:-$(id -un)}"
SO="/var/cache/hyprpm/${USER_NAME}/hyprland-plugins/hyprbars.so"

if hyprctl plugins list 2>/dev/null | grep -qi 'hyprbars'; then
    exit 0
fi

exec hyprctl plugin load "$SO"
