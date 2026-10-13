#!/usr/bin/env bash
set -euo pipefail

readonly STATE_DIR="$HOME/.cache/wallpaper-power"
readonly STATE_FILE="$STATE_DIR/last-power"
readonly SOURCE_FILE="$HOME/.config/wallpaper-source"
readonly MACHINE_FILE="$HOME/.config/machine-type"
readonly SWITCH="$HOME/.local/bin/wallpaper-switch.sh"
readonly DEFAULT_SOURCE="static"

is_laptop() {
    [ -f "$MACHINE_FILE" ] && [ "$(cat "$MACHINE_FILE")" = "laptop" ]
}

has_battery() {
    compgen -G '/sys/class/power_supply/BAT*' > /dev/null 2>&1
}

on_battery() {
    local path
    for path in /sys/class/power_supply/*/online; do
        [ -f "$path" ] || continue
        case "$path" in */BAT*) continue ;; esac
        if [ "$(cat "$path" 2>/dev/null)" = "1" ]; then
            return 1
        fi
    done
    return 0
}

current_power() {
    if on_battery; then
        printf 'battery'
    else
        printf 'ac'
    fi
}

stored_power() {
    [ -f "$STATE_FILE" ] && tr -d '[:space:]' < "$STATE_FILE" || true
}

source_mode() {
    if is_laptop; then
        printf 'static'
        return 0
    fi
    if [ -f "$SOURCE_FILE" ]; then
        tr -d '[:space:]' < "$SOURCE_FILE"
    else
        printf '%s' "$DEFAULT_SOURCE"
    fi
}

apply_battery() {
    if is_laptop; then
        "$SWITCH" use static
    else
        "$SWITCH" use frame
    fi
}

apply_ac() {
    "$SWITCH" use "$(source_mode)"
}

confirm_power() {
    local first="$1"
    sleep 3
    [ "$(current_power)" = "$first" ]
}

main() {
    if ! has_battery; then
        return 0
    fi
    local force="0" argument
    for argument in "$@"; do
        [ "$argument" = "--force" ] && force="1"
    done
    local current
    current="$(current_power)"
    if [ "$current" = "$(stored_power)" ] && [ "$force" != "1" ]; then
        return 0
    fi
    if [ "$force" != "1" ] && ! confirm_power "$current"; then
        return 0
    fi
    mkdir -p "$STATE_DIR"
    printf '%s' "$current" > "$STATE_FILE"
    if [ "$current" = "battery" ]; then
        apply_battery
    else
        apply_ac
    fi
}

main "$@"
