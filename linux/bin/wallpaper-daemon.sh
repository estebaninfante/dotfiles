#!/usr/bin/env bash
# Daemon de wallpaper animado (Wallpaper Engine nativo).
# Lee la config desde ~/.config/wallpaper-current y ~/.config/wallpaper-scaling.
# Asi el wallpaper elegido con `wall` persiste entre sesiones.
set -euo pipefail

CFG_DIR="$HOME/.config"
ID_FILE="$CFG_DIR/wallpaper-current"
SCALING_FILE="$CFG_DIR/wallpaper-scaling"
ASSETS="$HOME/.local/share/Steam/steamapps/common/wallpaper_engine/assets"
BIN="${LINUX_WALLPAPERENGINE:-$(command -v linux-wallpaperengine || echo /etc/profiles/per-user/$USER/bin/linux-wallpaperengine)}"

ID="${1:-$(cat "$ID_FILE" 2>/dev/null || echo 3464106929)}"
SCALING="$(cat "$SCALING_FILE" 2>/dev/null || echo fill)"

if [ -f "$CFG_DIR/machine-type" ] && [ "$(cat "$CFG_DIR/machine-type")" = "desktop" ]; then
  MONITORS="$(hyprctl monitors -j 2>/dev/null || true)"
  SCREEN="$(printf '%s' "$MONITORS" | jq -r '.[] | select(.name != "eDP-1") | .name' 2>/dev/null | head -1 || true)"
  SCREEN="${SCREEN:-DP-2}"
else
  SCREEN="eDP-1"
fi

exec "$BIN" \
  --assets-dir "$ASSETS" \
  --screen-root "$SCREEN" \
  --scaling "$SCALING" \
  --bg "$ID"
