#!/usr/bin/env bash
# sync-wallpaper.sh — propaga el fondo canonico de Omarchy a hyprpaper + hyprexpo.
#
# Fuente unica: ~/.local/state/omarchy/current/background (lo escribe
# `omarchy theme bg set`). Sin esto, cada superficie va por su lado:
# la shell sigue el symlink, pero hyprpaper.conf y hyprexpo/background_image
# quedan con el wallpaper anterior hasta edicion manual.
#
# Fondo distinto por monitor: ~/.config/hypr/wallpaper-monitors.conf
# (`<salida> = <ruta>`). Los monitores sin linea siguen el canonico. Se aplica a
# hyprpaper Y al backdrop del overview por monitor, asi el escritorio y la grilla
# coinciden en cada pantalla aunque cada una tenga su propio wallpaper.
#
# Uso: sync-wallpaper.sh            (lee el symlink)
#      sync-wallpaper.sh <imagen>   (hace `omarchy theme bg set` + propaga)
# Instalado como hook theme-set: `omarchy hook install theme-set sync-wallpaper.sh`
set -euo pipefail

BG_LINK="$HOME/.local/state/omarchy/current/background"
HYPR_CONF="$HOME/.config/hypr/hyprpaper.conf"
MONITORS_CONF="$HOME/.config/hypr/wallpaper-monitors.conf"
if [ -f "$HOME/.config/machine-type" ] && [ "$(cat "$HOME/.config/machine-type")" = "laptop" ]; then
    HYPR_CONF="$HOME/.config/hypr/hyprpaper-laptop.conf"
fi

# Fondo de una salida: el propio si esta definido y existe, si no el canonico.
monitor_wallpaper() {
    local monitor="$1" fallback="$2" image=""
    if [ -f "$MONITORS_CONF" ]; then
        image="$(sed -n "s|^[[:space:]]*${monitor}[[:space:]]*=[[:space:]]*||p" "$MONITORS_CONF" | head -1 | sed 's|[[:space:]]*$||')"
    fi
    if [ -n "$image" ] && [ -f "$image" ]; then
        printf '%s' "$image"
    else
        printf '%s' "$fallback"
    fi
}

if [ $# -ge 1 ]; then
    omarchy theme bg set "$1"
fi

BG="$(realpath "$BG_LINK" 2>/dev/null || true)"
if [ -z "${BG:-}" ] || [ ! -f "$BG" ]; then
    echo "sync-wallpaper: symlink $BG_LINK roto o vacio (omitido)" >&2
    exit 0
fi

# 1. hyprpaper.conf apunta al mismo archivo (persistencia entre reinicios).
#    `changed` marca si el fondo canónico es distinto del que ya estaba: solo
#    entonces hace falta el reload del final.
changed=0
if [ -f "$HYPR_CONF" ] && grep -q 'path =' "$HYPR_CONF"; then
    current="$(sed -n 's|^[[:space:]]*path = ||p' "$HYPR_CONF" | head -1)"
    if [ "$current" != "$BG" ]; then
        changed=1
        sed -i "s|^\(\s*path = \).*|\1$BG|" "$HYPR_CONF"
    fi
else
    changed=1
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
#    hyprpaper solo re-lee la config al reiniciar. Cada monitor recibe el suyo de
#    wallpaper-monitors.conf (o el canonico si no tiene linea propia).
#    Sólo se aplica lo que está DISTINTO de lo que hyprpaper ya tiene: re-aplicar el
#    mismo archivo rearma su textura/transición y se ve como si el wallpaper de esa
#    pantalla se reiniciara cada 2 min (lo que hace el timer de red de seguridad).
if pgrep -x hyprpaper >/dev/null 2>&1; then
    monitors="$(hyprctl monitors -j 2>/dev/null | jq -r '.[].name // empty' 2>/dev/null || true)"
    [ -z "$monitors" ] && monitors="DP-2"
    active="$(hyprctl hyprpaper listactive 2>/dev/null || true)"
    for mon in $monitors; do
        target="$(monitor_wallpaper "$mon" "$BG")"
        current="$(printf '%s\n' "$active" | sed -n "s|^${mon}: ||p" | head -1)"
        [ "$current" = "$target" ] && continue
        hyprctl hyprpaper wallpaper "$mon,$target" >/dev/null 2>&1 || true
    done
fi

# 2b. Backdrop del overview (hyprexpo) por monitor: el MISMO archivo que hyprpaper
#     usa en esa salida. Sin esto la grilla pinta el fondo canonico en todas las
#     pantallas y con dos wallpapers distintos se ve "otro" fondo al abrirla. Con
#     un .so viejo (sin la opcion) el getoption falla y se omite.
if [ -f "$MONITORS_CONF" ] && hyprctl getoption plugin:hyprexpo:background_image_monitors >/dev/null 2>&1; then
    mapping=""
    while IFS='=' read -r mon path; do
        mon="$(printf '%s' "$mon" | sed 's|^[[:space:]]*||; s|[[:space:]]*$||')"
        path="$(printf '%s' "$path" | sed 's|^[[:space:]]*||; s|[[:space:]]*$||')"
        case "$mon" in ""|\#*) continue ;; esac
        [ -f "$path" ] || continue
        # El string viaja dentro de un eval de Lua: si tiene comillas, barra o el
        # separador, se descarta en vez de romper el parser.
        case "$path" in *'"'*|*\\*|*';'*) continue ;; esac
        mapping="$mapping$mon=$path;"
    done < "$MONITORS_CONF"
    hyprctl eval "hl.config({ plugin = { hyprexpo = { background_image_monitors = \"$mapping\" } } })" >/dev/null 2>&1 || true
fi

# 3. Reload SOLO si el fondo cambió de verdad. `wallpaper-sync.timer` corre
#    cada 2 minutos como red de seguridad; recargar sin cambios re-aplica la
#    config de monitores (en batería, el panel pasa a 60 Hz) y deja el OLED en
#    negro ~1.5 s. Eso se ve como "la pantalla se apaga y vuelve", cada 2 min.
if [ "${SYNC_WALLPAPER_NO_RELOAD:-0}" != "1" ] && [ "$changed" = 1 ]; then
    hyprctl reload >/dev/null 2>&1 || true
fi

echo "wallpaper sincronizado: $BG"
