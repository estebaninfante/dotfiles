#!/usr/bin/env bash
# lan-mouse-grid.sh — qué hacer con lan-mouse mientras la grilla (hyprexpo) está abierta.
#
# El problema real: con el puntero en el CLIENTE (la máquina que lo recibe), soltar la
# captura ahí hace que el HOST suelte también y el puntero se teletransporte al host
# (dos cursores, clics en el equipo equivocado). Así que:
#
#   off → si ESTA máquina es la que está capturando (capture: active), suelta; si no,
#         no toca nada (somos el cliente: el host tiene que seguir mandando el puntero).
#   on  → re-arma solo si nosotros lo habíamos soltado (marca en $XDG_RUNTIME_DIR).
#
# Uso: lan-mouse-grid.sh off|on|status
set -uo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/lan-mouse-grid"
MARK="$STATE_DIR/released-by-grid"
SELF="$(readlink -f "$0")"
CAPTURE="$(dirname "$SELF")/lan-mouse-capture.sh"
[ -x "$CAPTURE" ] || CAPTURE="lan-mouse-capture.sh"

capture_state() {
    "$CAPTURE" status 2>/dev/null | sed -n 's/^capture: //p' | head -1
}

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/lan-mouse-grid"
log() {
    mkdir -p "$LOG_DIR" 2>/dev/null || return 0
    printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG_DIR/log" 2>/dev/null || true
}

case "${1:-}" in
    off)
        mkdir -p "$STATE_DIR" 2>/dev/null || true
        # Solo si el puntero está saliendo de acá (nosotros capturamos). Si somos el
        # cliente (capture: released), no se toca: el host sigue mandando el puntero.
        if [ "$(capture_state)" = "active" ]; then
            log "off: eramos el host (capture active) -> suelto"
            "$CAPTURE" off >/dev/null 2>&1 || true
            : > "$MARK" 2>/dev/null || true
        else
            log "off: somos el cliente (capture $(capture_state)) -> no toco nada"
        fi
        ;;
    on)
        if [ -f "$MARK" ]; then
            log "on: habiamos soltado -> re-armo"
            rm -f "$MARK" 2>/dev/null || true
            "$CAPTURE" on >/dev/null 2>&1 || true
        else
            log "on: no habiamos soltado -> no toco nada"
        fi
        ;;
    status)
        printf 'capture: %s\nreleased-by-grid: %s\n' "$(capture_state)" "$([ -f "$MARK" ] && echo si || echo no)"
        ;;
    *)
        printf 'usage: %s off|on|status\n' "$(basename "$0")" >&2
        exit 2
        ;;
esac
