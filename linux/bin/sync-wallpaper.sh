#!/usr/bin/env bash
# sync-wallpaper.sh — propaga el fondo canonico de Omarchy a hyprpaper + hyprexpo.
#
# Fuente unica: ~/.local/state/omarchy/current/background (lo escribe
# `omarchy theme bg set`). Sin esto, cada superficie va por su lado:
# la shell sigue el symlink, pero hyprpaper.conf y hyprexpo/background_image
# quedan con el wallpaper anterior hasta edicion manual.
#
# Uso: sync-wallpaper.sh            (lee el symlink)
#      sync-wallpaper.sh <imagen>   (hace `omarchy theme bg set` + propaga)
# Instalado como hook theme-set: `omarchy hook install theme-set sync-wallpaper.sh`
set -euo pipefail

BG_LINK="$HOME/.local/state/omarchy/current/background"
HYPR_CONF="$HOME/.config/hypr/hyprpaper.conf"
if [ -f "$HOME/.config/machine-type" ] && [ "$(cat "$HOME/.config/machine-type")" = "laptop" ]; then
    HYPR_CONF="$HOME/.config/hypr/hyprpaper-laptop.conf"
fi

if [ $# -ge 1 ]; then
    omarchy theme bg set "$1"
fi

BG="$(realpath "$BG_LINK" 2>/dev/null || true)"
if [ -z "${BG:-}" ] || [ ! -f "$BG" ]; then
    echo "sync-wallpaper: symlink $BG_LINK roto o vacio (omitido)" >&2
    exit 0
fi

# 1. hyprpaper.conf apunta al mismo archivo (persistencia entre reinicios).
if [ -f "$HYPR_CONF" ] && grep -q 'path =' "$HYPR_CONF"; then
    sed -i "s|^\(\s*path = \).*|\1$BG|" "$HYPR_CONF"
fi

# 2. hyprpaper vivo: aplica sin reiniciar el daemon (v0.8+: solo `wallpaper mon,path`).
if pgrep -x hyprpaper >/dev/null 2>&1; then
    mon="$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // empty' 2>/dev/null || true)"
    [ -z "$mon" ] && mon="DP-2"
    hyprctl hyprpaper wallpaper "$mon,$BG" >/dev/null 2>&1 || true
fi

# 3. hyprexpo/background_image se resuelve desde el symlink en cada reload.
hyprctl reload >/dev/null 2>&1 || true

echo "wallpaper sincronizado: $BG"
