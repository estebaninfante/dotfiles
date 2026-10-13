#!/usr/bin/env bash
set -euo pipefail

export SYNC_WALLPAPER_NO_RELOAD="${SYNC_WALLPAPER_NO_RELOAD:-1}"

readonly SCRIPT_PATH="$(realpath "$0")"
readonly CONFIG_DIR="$HOME/.config"
readonly STATE_DIR="$HOME/.local/state/omarchy/current"
readonly FRAME_DIR="$HOME/.cache/wallpaper-frames"
readonly POWER_DIR="$HOME/.cache/wallpaper-power"
readonly WORKSHOP_DIR="$HOME/.steam/steam/steamapps/workshop/content/431960"
readonly ASSETS_DIR="$HOME/.local/share/Steam/steamapps/common/wallpaper_engine/assets"
readonly SOURCE_FILE="$CONFIG_DIR/wallpaper-source"
readonly ID_FILE="$CONFIG_DIR/wallpaper-current"
readonly SCALING_FILE="$CONFIG_DIR/wallpaper-scaling"
readonly MACHINE_FILE="$CONFIG_DIR/machine-type"
readonly BG_LINK="$STATE_DIR/background"
readonly SERVICE="linux-wallpaperengine.service"
readonly BIN="linux-wallpaperengine"
readonly DEFAULT_ID="3464106929"
readonly DEFAULT_SCALING="fill"
readonly DEFAULT_SOURCE="static"
readonly CAPTURE_TIMEOUT="${WALLPAPER_CAPTURE_TIMEOUT:-30}"
readonly SCREENSHOT_DELAY="${WALLPAPER_SCREENSHOT_DELAY:-10}"

read_state() {
    local file="$1" fallback="$2"
    if [ -f "$file" ]; then
        tr -d '[:space:]' < "$file"
    else
        printf '%s' "$fallback"
    fi
}

current_source() { read_state "$SOURCE_FILE" "$DEFAULT_SOURCE"; }
current_id() { read_state "$ID_FILE" "$DEFAULT_ID"; }
current_scaling() { read_state "$SCALING_FILE" "$DEFAULT_SCALING"; }

is_laptop() {
    [ -f "$MACHINE_FILE" ] && [ "$(cat "$MACHINE_FILE")" = "laptop" ]
}

effective_source() {
    if is_laptop; then
        printf 'static'
        return 0
    fi
    current_source
}

workshop_path() {
    local id="$1"
    if [ -d "$id" ]; then
        printf '%s' "$id"
    else
        printf '%s/%s' "$WORKSHOP_DIR" "$id"
    fi
}

frame_path() {
    printf '%s/%s.png' "$FRAME_DIR" "$1"
}

primary_monitor() {
    local monitor
    monitor="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .name' 2>/dev/null | head -1 || true)"
    if [ -n "$monitor" ]; then
        printf '%s' "$monitor"
        return 0
    fi
    hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // empty' 2>/dev/null || true
}

monitor_dims() {
    local monitor="$1"
    hyprctl monitors -j 2>/dev/null | jq -r --arg m "$monitor" '.[] | select(.name == $m) | "\(.width)x\(.height)"' 2>/dev/null || true
}

battery_state() {
    local path
    if ! compgen -G '/sys/class/power_supply/BAT*' > /dev/null 2>&1; then
        printf 'sin-bateria'
        return 0
    fi
    for path in /sys/class/power_supply/*/online; do
        [ -f "$path" ] || continue
        case "$path" in */BAT*) continue ;; esac
        if [ "$(cat "$path" 2>/dev/null)" = "1" ]; then
            printf 'ac'
            return 0
        fi
    done
    printf 'bateria'
}

hyprpaper_conf() {
    if is_laptop; then
        printf '%s' "$CONFIG_DIR/hypr/hyprpaper-laptop.conf"
    else
        printf '%s' "$CONFIG_DIR/hypr/hyprpaper.conf"
    fi
}

list_wallpapers() {
    local dir id title
    if [ ! -d "$WORKSHOP_DIR" ]; then
        echo "Sin wallpapers de workshop en $WORKSHOP_DIR" >&2
        return 0
    fi
    local active
    active="$(current_id)"
    for dir in "$WORKSHOP_DIR"/*/; do
        [ -d "$dir" ] || continue
        id="$(basename "$dir")"
        title="$(jq -r '.title // .file // "?"' "$dir/project.json" 2>/dev/null || echo '?')"
        if [ "$id" = "$active" ]; then
            printf '* %s  %s\n' "$id" "$title"
        else
            printf '  %s  %s\n' "$id" "$title"
        fi
    done
}

start_hyprpaper() {
    local conf
    conf="$(hyprpaper_conf)"
    if ! pgrep -x hyprpaper > /dev/null 2>&1; then
        setsid hyprpaper --config "$conf" > /dev/null 2>&1 &
        disown 2>/dev/null || true
        sleep 1
    fi
    "$HOME/.local/bin/sync-wallpaper.sh" > /dev/null 2>&1 || true
}

stop_hyprpaper() {
    pkill -x hyprpaper > /dev/null 2>&1 || true
}

save_pre_frame_bg() {
    local frame="$1"
    local saved="$POWER_DIR/pre-frame-bg" marker="$POWER_DIR/frame-bg" current
    [ -f "$saved" ] && return 0
    mkdir -p "$POWER_DIR"
    current="$(realpath "$BG_LINK" 2>/dev/null || true)"
    if [ -n "$current" ] && [ -f "$current" ]; then
        printf '%s' "$current" > "$saved"
        printf '%s' "$frame" > "$marker"
    fi
}

restore_bg() {
    local saved="$POWER_DIR/pre-frame-bg" marker="$POWER_DIR/frame-bg"
    local background frame current
    [ -f "$saved" ] || return 0
    background="$(cat "$saved" 2>/dev/null || true)"
    frame="$(cat "$marker" 2>/dev/null || true)"
    current="$(realpath "$BG_LINK" 2>/dev/null || true)"
    rm -f "$saved" "$marker"
    if [ -n "$frame" ] && [ "$current" != "$frame" ]; then
        return 0
    fi
    if [ -n "$background" ] && [ -f "$background" ]; then
        "$HOME/.local/bin/sync-wallpaper.sh" "$background" > /dev/null 2>&1 || true
        printf '%s' "$background"
    fi
}

capture_frame() {
    local id="${1:-$(current_id)}"
    local source_dir frame monitor dims tmp pid waited
    source_dir="$(workshop_path "$id")"
    if [ ! -d "$source_dir" ]; then
        echo "wallpaper no encontrado: $id" >&2
        return 1
    fi
    if ! command -v "$BIN" > /dev/null 2>&1; then
        echo "falta $BIN (instalar linux-wallpaperengine-git)" >&2
        return 1
    fi
    monitor="$(primary_monitor)"
    if [ -z "$monitor" ]; then
        echo "sin monitor disponible" >&2
        return 1
    fi
    dims="$(monitor_dims "$monitor")"
    mkdir -p "$FRAME_DIR"
    frame="$(frame_path "$id")"
    tmp="$(mktemp "$FRAME_DIR/.$id.XXXXXX.png")"
    timeout "$CAPTURE_TIMEOUT" "$BIN" \
        --assets-dir "$ASSETS_DIR" \
        --screen-root "$monitor" \
        --scaling "$(current_scaling)" \
        --layer bottom \
        --screenshot "$tmp" \
        --screenshot-delay "$SCREENSHOT_DELAY" \
        --silent \
        --bg "$id" > /dev/null 2>&1 &
    pid=$!
    waited=0
    while [ ! -s "$tmp" ] && [ "$waited" -lt "$CAPTURE_TIMEOUT" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    local last_size=-1 current_size=0 stable=0 valid=0
    while [ "$waited" -lt "$CAPTURE_TIMEOUT" ] && [ "$valid" = "0" ]; do
        current_size="$(stat -c%s "$tmp" 2>/dev/null || echo 0)"
        if [ "$current_size" = "$last_size" ] && [ "$current_size" -gt 0 ]; then
            stable=$((stable + 1))
        else
            stable=0
        fi
        last_size="$current_size"
        if [ "$stable" -ge 2 ]; then
            if ! command -v magick > /dev/null 2>&1 || magick identify "$tmp" > /dev/null 2>&1; then
                valid=1
                break
            fi
        fi
        sleep 1
        waited=$((waited + 1))
    done
    kill "$pid" > /dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
    pkill -f -- "--screenshot $tmp" > /dev/null 2>&1 || true
    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        echo "captura fallida para $id" >&2
        return 1
    fi
    if command -v magick > /dev/null 2>&1 && ! magick identify "$tmp" > /dev/null 2>&1; then
        rm -f "$tmp"
        echo "captura corrupta para $id" >&2
        return 1
    fi
    if command -v magick > /dev/null 2>&1 && [ -n "$dims" ]; then
        if ! magick "$tmp" -resize "${dims}!" "$frame" 2>/dev/null; then
            mv "$tmp" "$frame"
        fi
    else
        mv "$tmp" "$frame"
    fi
    rm -f "$tmp"
    printf '%s\n' "$frame"
}

capture_frame_async() {
    local id="$1"
    setsid "$SCRIPT_PATH" frame "$id" > /dev/null 2>&1 &
    disown 2>/dev/null || true
}

use_video() {
    if is_laptop; then
        echo "wallpaper: laptop usa siempre fondo estatico; redirigiendo a static" >&2
        use_static
        return 0
    fi
    local id frame
    if ! command -v "$BIN" > /dev/null 2>&1; then
        echo "falta $BIN (instalar linux-wallpaperengine-git)" >&2
        return 1
    fi
    id="$(current_id)"
    if [ ! -d "$(workshop_path "$id")" ]; then
        echo "wallpaper $id no descargado" >&2
        return 1
    fi
    printf '%s' 'video' > "$SOURCE_FILE"
    stop_hyprpaper
    restore_bg > /dev/null 2>&1 || true
    systemctl --user restart "$SERVICE" > /dev/null 2>&1 || systemctl --user start "$SERVICE" > /dev/null 2>&1 || true
    frame="$(frame_path "$id")"
    [ -f "$frame" ] || capture_frame_async "$id"
    echo "fondo: video (linux-wallpaperengine, id $id)"
}

use_static() {
    printf '%s' 'static' > "$SOURCE_FILE"
    systemctl --user stop "$SERVICE" > /dev/null 2>&1 || true
    restore_bg > /dev/null 2>&1 || true
    start_hyprpaper
    echo "fondo: estatico (hyprpaper sobre el fondo canonico de Omarchy)"
}

use_frame() {
    local id frame
    id="$(current_id)"
    frame="$(frame_path "$id")"
    if [ ! -f "$frame" ]; then
        echo "sin frame cacheado para $id; capturando" >&2
        frame="$(capture_frame "$id")" || frame=""
    fi
    systemctl --user stop "$SERVICE" > /dev/null 2>&1 || true
    if [ -z "$frame" ] || [ ! -f "$frame" ]; then
        echo "fondo: estatico (canonico, sin frame; fuente sin cambios)" >&2
        start_hyprpaper
        return 0
    fi
    save_pre_frame_bg "$frame"
    start_hyprpaper
    "$HOME/.local/bin/sync-wallpaper.sh" "$frame"
    echo "fondo: frame estatico ($id; fuente sin cambios) $frame"
}

set_wallpaper() {
    local id="$1" capture="${2:-1}"
    if is_laptop; then
        echo "wallpaper: laptop usa siempre fondo estatico; redirigiendo a static" >&2
        use_static
        return 0
    fi
    if [ ! -d "$(workshop_path "$id")" ]; then
        echo "no existe wallpaper: $id" >&2
        list_wallpapers >&2
        return 1
    fi
    printf '%s' "$id" > "$ID_FILE"
    restore_bg > /dev/null 2>&1 || true
    use_video
    if [ "$capture" = "1" ]; then
        capture_frame_async "$id"
        echo "frame en background: $(frame_path "$id")"
    fi
}

show_status() {
    local engine hypr
    engine="$(systemctl --user is-active "$SERVICE" 2>/dev/null || true)"
    if pgrep -x hyprpaper > /dev/null 2>&1; then hypr="activo"; else hypr="inactivo"; fi
    printf 'source:    %s\n' "$(effective_source)"
    printf 'id:        %s\n' "$(current_id)"
    printf 'scaling:   %s\n' "$(current_scaling)"
    printf 'engine:    %s\n' "${engine:-inactivo}"
    printf 'hyprpaper: %s\n' "$hypr"
    printf 'frame:     %s\n' "$(frame_path "$(current_id)")"
    printf 'energia:   %s\n' "$(battery_state)"
}

usage() {
    cat << 'EOF'
Uso: wallpaper-switch.sh <comando>

  list                      lista wallpapers de workshop (marca el activo)
  use video                 fondo animado (linux-wallpaperengine), sin relogin
  use static                fondo estatico (hyprpaper + fondo canonico Omarchy)
  use frame                 frame congelado cacheado (fuente sin cambios)
  use static --frame        alias de `use frame`
  set <id> [--no-frame]     fija wallpaper de video y captura su frame
  frame [<id>]              captura (o recaptura) el frame estatico cacheado
  scaling <modo>            stretch|fit|fill|default
  status                    estado actual (fuente, id, engine, frame, energia)
  reset                     vuelve al wallpaper por defecto
EOF
}

case "${1:-}" in
    ""|-l|list)
        list_wallpapers
        echo
        usage
        ;;
    use)
        shift || true
        mode="${1:-}"
        shift || true
        frame_flag=0
        restore_flag=0
        for argument in "$@"; do
            case "$argument" in
                --frame) frame_flag=1 ;;
                --restore-bg) restore_flag=1 ;;
                *) ;;
            esac
        done
        [ "$restore_flag" = "1" ] && { restore_bg > /dev/null 2>&1 || true; }
        case "$mode" in
            video) use_video ;;
            frame) use_frame ;;
            static)
                if [ "$frame_flag" = "1" ]; then
                    use_frame
                else
                    use_static
                fi
                ;;
            *)
                usage >&2
                exit 1
                ;;
        esac
        ;;
    set)
        id="${2:-}"
        if [ -z "$id" ]; then
            usage >&2
            exit 1
        fi
        capture_flag=1
        [ "${3:-}" = "--no-frame" ] && capture_flag=0
        set_wallpaper "$id" "$capture_flag"
        ;;
    frame)
        capture_frame "${2:-$(current_id)}"
        ;;
    scaling)
        mode="${2:-}"
        case "$mode" in
            stretch|fit|fill|default)
                printf '%s' "$mode" > "$SCALING_FILE"
                if systemctl --user is-active --quiet "$SERVICE" 2>/dev/null; then
                    systemctl --user restart "$SERVICE" > /dev/null 2>&1 || true
                fi
                echo "scaling: $mode (persistente)"
                ;;
            *)
                echo "modos: stretch|fit|fill|default" >&2
                exit 1
                ;;
        esac
        ;;
    status)
        show_status
        ;;
    reset)
        printf '%s' "$DEFAULT_ID" > "$ID_FILE"
        printf '%s' "$DEFAULT_SCALING" > "$SCALING_FILE"
        set_wallpaper "$DEFAULT_ID" 1
        ;;
    *)
        set_wallpaper "$1" 1
        ;;
esac
