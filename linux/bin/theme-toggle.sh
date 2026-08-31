#!/usr/bin/env bash
# Toggle tema global claro↔oscuro para legibilidad (día/noche).
# Orquesta: kitty, GTK color-scheme, wallpaper (hyprpaper IPC) y notifica.
# El modo CANONICO es linux/config/kitty/active-theme.conf (symlink al repo
# trackeado por git): aqui se deriva el modo con readlink y el resto sigue.
set -euo pipefail

REPO="$HOME/dotfiles"
KITTY_DIR="$REPO/linux/config/kitty"
ACTIVE="$KITTY_DIR/active-theme.conf"
WP_DIR="$HOME/.config/hypr/wallpapers"          # symlink a linux/config/hypr/wallpapers
HYPR_CONF="$HOME/.config/hypr/hyprpaper.conf"   # fallback de maquina desktop
if [ -f "$HOME/.config/machine-type" ] && [ "$(cat "$HOME/.config/machine-type")" = "laptop" ]; then
    HYPR_CONF="$HOME/.config/hypr/hyprpaper-laptop.conf"
fi

current_mode() {
    readlink "$ACTIVE" 2>/dev/null | grep -o 'theme-[a-z]*' | sed 's/theme-//'
}

# ── Resolver modo objetivo ────────────────────────────────
target="$1"
case "$target" in
    light|dark) ;;
    toggle|"")
        cur="$(current_mode || echo dark)"
        if [ "$cur" = "light" ]; then target=dark; else target=light; fi
        ;;
    *)
        echo "uso: theme-toggle.sh [light|dark|toggle]" >&2
        exit 1
        ;;
esac

# ── 1. Kitty (modo canonico; kitty recarga sola al cambiar) ──
kitty-theme-toggle.sh "$target"

# ── 2. GTK / apps (color-scheme global) ───────────────────
if command -v gsettings >/dev/null 2>&1; then
    pref="prefer-dark"; [ "$target" = "light" ] && pref="prefer-light"
    gsettings set org.gnome.desktop.interface color-scheme "$pref" 2>/dev/null || true
fi

# ── 3. Wallpaper (hyprpaper IPC; desktop con Wallpaper Engine lo pausa) ──
apply_wallpaper() {
    local img
    if [ "$target" = "light" ]; then
        img="$WP_DIR/porsche_white.jpg"
    else
        img="$WP_DIR/porsche_wallpaper.jpg"
    fi
    if [ ! -f "$img" ]; then
        echo "wallpaper: no existe $img (omitido)" >&2
        return 0
    fi
    # Desktop con Wallpaper Engine activo → pararlo y usar hyprpaper (jpg estatico)
    if systemctl --user is-active --quiet linux-wallpaperengine.service 2>/dev/null; then
        systemctl --user stop linux-wallpaperengine.service 2>/dev/null || true
    fi
    if ! pgrep -x hyprpaper >/dev/null 2>&1; then
        setsid nohup hyprpaper --config "$HYPR_CONF" >/dev/null 2>&1 &
        sleep 0.8
    fi
    local mon
    mon="$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // empty' 2>/dev/null)"
    [ -z "$mon" ] && mon="eDP-1"
    # hyprpaper v0.8+: IPC string solo soporta `wallpaper <mon>,<path>`
    # (reload/preload/unload eliminados). fit_mode default = cover (igual al config).
    hyprctl hyprpaper wallpaper "$mon,$img" >/dev/null 2>&1 || true
}
apply_wallpaper

# ── 4. Notificar ──────────────────────────────────────────
if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "theme-toggle" "Tema $target" "Kitty · GTK · wallpaper cambiados" 2>/dev/null || true
fi

echo "theme global: $target"
