#!/usr/bin/env bash
set -euo pipefail

readonly CONFIG_DIR="$HOME/.config"
readonly MACHINE_FILE="$CONFIG_DIR/machine-type"
readonly ID_FILE="$CONFIG_DIR/wallpaper-current"
readonly SCALING_FILE="$CONFIG_DIR/wallpaper-scaling"
readonly DEFAULT_ID="3464106929"
readonly DEFAULT_SCALING="fill"

is_laptop() {
    [ -f "$MACHINE_FILE" ] && [ "$(cat "$MACHINE_FILE")" = "laptop" ]
}

if is_laptop; then
    "$HOME/.local/bin/wallpaper-switch.sh" use static > /dev/null 2>&1 || true
    echo "wallpaper-daemon: laptop usa fondo estatico; engine no arranca" >&2
    exit 0
fi

resolve_assets() {
    local candidate
    for candidate in \
        "$HOME/.local/share/Steam/steamapps/common/wallpaper_engine/assets" \
        "$HOME/.steam/steam/steamapps/common/wallpaper_engine/assets"; do
        if [ -d "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    printf '%s' "$HOME/.local/share/Steam/steamapps/common/wallpaper_engine/assets"
}

resolve_binary() {
    if [ -n "${LINUX_WALLPAPERENGINE:-}" ]; then
        printf '%s' "$LINUX_WALLPAPERENGINE"
        return 0
    fi
    command -v linux-wallpaperengine 2>/dev/null || printf '%s' /usr/bin/linux-wallpaperengine
}

resolve_screen() {
    if [ -n "${WALLPAPER_SCREEN:-}" ]; then
        printf '%s' "$WALLPAPER_SCREEN"
        return 0
    fi
    local monitors focused
    monitors="$(hyprctl monitors -j 2>/dev/null || true)"
    focused="$(printf '%s' "$monitors" | jq -r '.[] | select(.focused == true) | .name' 2>/dev/null | head -1 || true)"
    if [ -n "$focused" ]; then
        printf '%s' "$focused"
        return 0
    fi
    printf '%s' "$monitors" | jq -r '.[0].name // empty' 2>/dev/null || printf '%s' eDP-2
}

read_state() {
    local file="$1" fallback="$2"
    if [ -f "$file" ]; then
        tr -d '[:space:]' < "$file"
    else
        printf '%s' "$fallback"
    fi
}

readonly ASSETS="$(resolve_assets)"
readonly BIN="$(resolve_binary)"
readonly SCREEN="$(resolve_screen)"
readonly ID="${1:-$(read_state "$ID_FILE" "$DEFAULT_ID")}"
readonly SCALING="$(read_state "$SCALING_FILE" "$DEFAULT_SCALING")"

exec "$BIN" \
    --assets-dir "$ASSETS" \
    --screen-root "$SCREEN" \
    --scaling "$SCALING" \
    --layer bottom \
    --bg "$ID"
