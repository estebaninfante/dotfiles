#!/usr/bin/env bash
set -euo pipefail

CLASS="herdr"
START_DIR="${HOME:-/home/eztvn}"

existing=$(hyprctl clients -j | jq -r --arg c "$CLASS" 'map(select(.class == $c)) | .[0].address // empty')

if [ -n "$existing" ]; then
    hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:${existing}' }))"
    exit 0
fi

setsid kitty --class "$CLASS" --title "herdr" --directory "$START_DIR" herdr >/dev/null 2>&1 </dev/null &
