#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="$HOME/.local/state/opencode"
STATE_FILE="$STATE_DIR/notify-push-enabled"

mkdir -p "$STATE_DIR"

if [ -f "$STATE_FILE" ] && [ "$(<"$STATE_FILE")" = "1" ]; then
  printf '0\n' > "$STATE_FILE"
  notify --app-name OpenCode -g "󰏲" "Notify celular desactivado"
else
  printf '1\n' > "$STATE_FILE"
  notify --app-name OpenCode -g "󰏲" "Notify celular activado"
fi
