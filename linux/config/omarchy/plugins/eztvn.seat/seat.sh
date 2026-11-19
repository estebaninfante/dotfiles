#!/usr/bin/env bash
# seat.sh — puente de estado para el indicador del Agent Seat en la barra.
#
# Uso:
#   seat.sh status   -> una línea JSON: {"running":bool,"windows":N,"titles":"…"}
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
    jq -cn --argjson running "$running" --argjson windows "${windows:-0}" --arg titles "$titles" \
        '{running: $running, windows: $windows, titles: $titles}'
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
