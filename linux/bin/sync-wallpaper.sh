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

# 1b. Overview (hyprexpo): pasarle la ruta nueva en caliente si el plugin ya esta
#     cargado. Con el .so nuevo es redundante (resuelve el symlink y cachea por
#     mtime en cada apertura), pero en una maquina con el build anterior evita que
#     la grilla siga mostrando el fondo viejo (dos wallpapers hasta el reload).
if [[ "$BG" != *'"'* && "$BG" != *\\* ]]; then
    hyprctl eval "hl.config({ plugin = { hyprexpo = { background_image = \"$BG\" } } })" >/dev/null 2>&1 || true
fi

# 2. hyprpaper vivo: aplica sin reiniciar el daemon (v0.8+: solo `wallpaper mon,path`).
#    A TODOS los monitors: aplicar solo a `.[0]` dejaba el segundo con el fondo viejo
#    (con un monitor virtual de Sunshine el escritorio y el stream no coincidian) y
#    hyprpaper solo re-lee la config al reiniciar.
if pgrep -x hyprpaper >/dev/null 2>&1; then
    monitors="$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name // empty' 2>/dev/null || true)"
    [ -z "$monitors" ] && monitors="DP-2"
    for mon in $monitors; do
        hyprctl hyprpaper wallpaper "$mon,$BG" >/dev/null 2>&1 || true
    done
fi

if [ "${SYNC_WALLPAPER_NO_RELOAD:-0}" != "1" ]; then
    hyprctl reload >/dev/null 2>&1 || true
fi

echo "wallpaper sincronizado: $BG"
