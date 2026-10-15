#!/usr/bin/env bash
set -uo pipefail

USER_NAME="${USER:-$(id -un)}"
SO="/var/cache/hyprpm/${USER_NAME}/hyprexpo/hyprexpo.so"

if hyprctl plugins list 2>/dev/null | grep -qi 'hyprexpo'; then
    exit 0
fi

exec hyprctl plugin load "$SO"
