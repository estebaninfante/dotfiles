#!/usr/bin/env bash
# Puente Hyprland -> input-remapper: decide el preset activo del gamepad
# segun la ventana enfocada.
#
# Problema que resuelve (doble input): input-remapper "roba" el pad (grab)
# y re-emite teclado virtual. Si un juego queda enfocado con la capa UI
# activa, el juego solo recibiria teclado (el pad nativo no llega). Este
# puente hace `stop` (pad 100% nativo) cuando hay un juego fullscreen
# enfocado, y reactiva el preset `desktop` (pad -> kb/raton) en la UI.
#
# Escucha eventos de Hyprland por el socket2 (.socket2.sock). Solo actua
# cuando cambia la ventana activa; re-evalua tambien en closewindow para
# cubrir el "el juego murió y el foco volvió a cartridges".
set -euo pipefail

DEVICE="Nintendo Wii Remote Pro Controller"
PRESET_DESKTOP="desktop"
FLAG=/tmp/gamemode.flag

# Clases donde la navegacion por mando debe seguir activa (UI del sistema).
UI_ALLOW='cartridges|quickshell|waybar|swaync|swayosd|hypr|kitty|firefox|discord|whatsapp|whatsie|spotify|sunshine|org\.kde\.dolphin|libreoffice|soffice|opencode|tmux|ulauncher'

state=unknown   # unknown | desktop | stop

active_state() {
    local class fs
    class=$(hyprctl -j activewindow 2>/dev/null | jq -r '.class' 2>/dev/null || echo "")
    fs=$(hyprctl -j activewindow 2>/dev/null | jq -r '.fullscreen' 2>/dev/null || echo "0")

    # Sin ventana o fuera de modo juego: navegacion de escritorio.
    if [ -z "$class" ] || [ ! -f "$FLAG" ]; then
        echo "desktop"; return
    fi
    # UI del sistema (incl. cartridges fullscreen): mando navega.
    if echo "$class" | grep -qiE "$UI_ALLOW"; then
        echo "desktop"; return
    fi
    # Juego (window no-UI fullscreen dentro de modo juego): pad nativo.
    if [ "$fs" = "1" ] || [ "$fs" = "2" ]; then
        echo "stop"; return
    fi
    echo "desktop"
}

apply_state() {
    local want="$1"
    [ "$want" = "$state" ] && return
    case "$want" in
        desktop)
            input-remapper-control --command start --device "$DEVICE" --preset "$PRESET_DESKTOP" >/dev/null 2>&1 || true
            ;;
        stop)
            input-remapper-control --command stop --device "$DEVICE" >/dev/null 2>&1 || true
            ;;
    esac
    state="$want"
}

refresh() {
    apply_state "$(active_state)"
}

while true; do
    socket=$(ls -t "$XDG_RUNTIME_DIR"/hypr/*/.socket2.sock 2>/dev/null | head -n1 || true)
    if [ -z "$socket" ]; then
        sleep 2
        continue
    fi
    # Linea inicial: aplicar estado actual nada mas conectar.
    refresh
    socat -U - "UNIX-CONNECT:$socket" | while IFS= read -r line; do
        case "$line" in
            activewindow\>\>*|activewindowv2\>\>*|closewindow\>\>*)
                refresh
                ;;
        esac
    done || true
    sleep 1
done