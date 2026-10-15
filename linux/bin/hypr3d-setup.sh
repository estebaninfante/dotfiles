#!/usr/bin/env bash
set -uo pipefail

HYPR3D_LOAD="$HOME/.local/bin/hypr3d-load.sh"
PANORAMA="$HOME/.local/share/hypr3d/space.png"
MAP="$HOME/.local/share/hypr3d/space.glb"

"$HYPR3D_LOAD" >/dev/null 2>&1 || true

for _ in 1 2 3 4 5; do
    if hyprctl plugins list 2>/dev/null | grep -qi 'hypr3d'; then
        break
    fi
    sleep 1
done

hyprctl eval "hl.plugin.hypr3d.config({ world = { panorama = '$PANORAMA', grid = false }, windows = { focus_on_aim = false }, player = { flying = true, spawn = { x = 0, y = 2, z = 16 } }, map = { path = '$MAP', collision = true, flat = false, emissive_scale = 1.0 } })" || true
