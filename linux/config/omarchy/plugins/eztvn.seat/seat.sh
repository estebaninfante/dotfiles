#!/usr/bin/env bash
# seat.sh — puente de estado para el indicador y el botón del Agent Seat.
#
# Uso:
#   seat.sh status   -> {"running":bool,"windows":N,"titles":"…","where":"seat|user"}
#   seat.sh show     -> salta a la ventana más nueva del asiento
#   seat.sh stop     -> cierra broker y sandboxes
#
# Nunca toca la sesión del usuario: sólo lee el estado del asiento.
set -uo pipefail

AGENTE="$(command -v agent-seat 2>/dev/null || echo "$HOME/.local/bin/agent-seat")"

case "${1:-status}" in
status)
    running=false
    if "$AGENTE" status 2>/dev/null | grep -q "Agent seat: running"; then
        running=true
    fi
    windows=0
    titles=""
    if [ "$running" = true ]; then
        JSON="$("$AGENTE" windows 2>/dev/null || true)"
        windows="$(printf '%s' "$JSON" | jq -r 'if type == "array" then length else 0 end' 2>/dev/null || echo 0)"
        titles="$(printf '%s' "$JSON" | jq -r '[.[] | .title] | join(" · ")' 2>/dev/null || true)"
    fi
    # ¿la ventana activa es del asiento? lo usa el botón para mostrar ir/volver.
    clase="$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty' 2>/dev/null || true)"
    where="user"
    case "$clase" in
    agent-*) where="seat" ;;
    esac
    jq -cn --argjson running "$running" --argjson windows "${windows:-0}" \
        --arg titles "$titles" --arg where "$where" \
        '{running: $running, windows: $windows, titles: $titles, where: $where}'
    ;;
show)
    exec "$AGENTE" show
    ;;
stop)
    exec "$AGENTE" stop
    ;;
*)
    echo "uso: seat.sh status|show|stop" >&2
    exit 1
    ;;
esac
