#!/usr/bin/env bash
# Rueda del medio (mouse:274), comportamiento condicional:
# - Warp enfocado → Ctrl derecho MANTENIDO mientras se mantiene la rueda.
#   keydown/keyup explicitos via dotoolc → dotoold (device uinput
#   persistente). Matar el proceso NO libera la tecla (quedaba pegada);
#   el release simetrico por el mismo device es lo que la suelta.
#   dotool en vez de wtype porque Warp ignora virtual-keyboard de Wayland.
# - Resto         → Handy toggle post-procesado (equivale a F7, solo toggle).
set -euo pipefail

action="${1:-down}"
send() { printf '%s\n' "$1" | dotoolc >/dev/null 2>&1 || true; }

case "$action" in
down)
    class="$(hyprctl -j activewindow 2>/dev/null | jq -r '.class // empty')"
    if [ "$class" = "dev.warp.Warp" ]; then
        send "keyup rightctrl"
        send "keydown rightctrl"
    else
        exec handy --toggle-post-process
    fi
    ;;
up)
    send "keyup rightctrl"
    ;;
esac
