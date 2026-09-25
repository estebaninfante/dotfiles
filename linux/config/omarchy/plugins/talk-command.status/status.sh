#!/usr/bin/env bash
# talk-command status bridge for the Omarchy bar widget.
#
# Usage:
#   status.sh status           -> prints one JSON line with the service state
#   status.sh toggle           -> start if inactive, stop if active
#   status.sh start | stop     -> explicit control
#
# The widget reads a single JSON object; nothing here talks to the network.
set -euo pipefail

UNIT="${TALK_COMMAND_UNIT:-talk-command.service}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/talk-command/config.yaml"
KEYWORDS="${XDG_DATA_HOME:-$HOME/.local/share}/talk-command/keywords"

service_state() {
  if systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
    echo "active"
  elif systemctl --user is-enabled --quiet "$UNIT" 2>/dev/null; then
    echo "inactive"
  else
    echo "disabled"
  fi
}

keyword_count() {
  local n=0
  if [[ -d "$KEYWORDS" ]]; then
    shopt -s nullglob
    local files=("$KEYWORDS"/*.npz)
    n=${#files[@]}
  fi
  echo "$n"
}

print_status() {
  local state count engine
  state="$(service_state)"
  count="$(keyword_count)"
  engine="acoustic"
  if [[ -f "$CONFIG" ]]; then
    local parsed
    parsed="$(sed -n 's/^[[:space:]]*engine:[[:space:]]*//p' "$CONFIG" | head -1)"
    [[ -n "$parsed" ]] && engine="$parsed"
  fi
  printf '{"state":"%s","unit":"%s","keywords":%s,"engine":"%s","updatedAt":%s}\n' \
    "$state" "$UNIT" "$count" "$engine" "$(date +%s%3N)"
}

case "${1:-status}" in
  status) print_status ;;
  start)  systemctl --user start "$UNIT" ;;
  stop)   systemctl --user stop "$UNIT" ;;
  toggle)
    if systemctl --user is-active --quiet "$UNIT" 2>/dev/null; then
      systemctl --user stop "$UNIT"
      notify-send -a talk-command -i audio-input-microphone "talk-command" "Escucha pausada" 2>/dev/null || true
    else
      systemctl --user start "$UNIT"
      notify-send -a talk-command -i audio-input-microphone "talk-command" "Escuchando wake words" 2>/dev/null || true
    fi
    ;;
  *) echo "uso: status.sh [status|start|stop|toggle]" >&2; exit 2 ;;
esac
