#!/usr/bin/env bash
set -uo pipefail

SO="$HOME/.local/share/hypr3d-src/build/hypr3d.so"

if hyprctl plugins list 2>/dev/null | grep -qi 'hypr3d'; then
    exit 0
fi

exec hyprctl plugin load "$SO"
