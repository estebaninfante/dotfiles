#!/usr/bin/env bash
# Cambia el wallpaper animado de Wallpaper Engine SIN hacer rebuild.
#   (sin args)                : lista wallpapers de workshop descargados
#   wallpaper-switch.sh <id|path> : pon ese wallpaper al instante
#   wallpaper-switch.sh reset     : vuelve al wallpaper por defecto (home.nix)
# Los ids de workshop viven en steamapps/workshop/content/431960/<id>/
# Tambien acepta una ruta local a una carpeta de proyecto.
set -euo pipefail

WORKSHOP="$HOME/.steam/steam/steamapps/workshop/content/431960"
ASSETS="$HOME/.local/share/Steam/steamapps/common/wallpaper_engine/assets"
BIN="$(command -v linux-wallpaperengine)"
SERVICE="linux-wallpaperengine.service"
# Pantalla principal por maquina (coincide con home.nix / hyprland.lua)
machine="$(cat "$HOME/.config/machine-type" 2>/dev/null || echo laptop)"
SCREEN="${SCREEN:-$( [ "$machine" = "desktop" ] && echo DP-1 || echo eDP-1 )}"
SCALING="${SCALING:-fill}"

list_wallpapers() {
  local dirs
  mapfile -t dirs < <(find "$WORKSHOP" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  if [ "${#dirs[@]}" -eq 0 ]; then
    echo "No hay wallpapers de workshop descargados aun."
    return
  fi
  local d
  for d in "${dirs[@]}"; do
    local id name
    id="$(basename "$d")"
    name="$(jq -r '.file|split(".")[0] // .name' "$d/project.json" 2>/dev/null || echo '?')"
    printf "%s  %s\n" "$id" "$name"
  done
}

run_manual() { # $1 = id o path de wallpaper
  systemctl --user stop "$SERVICE" 2>/dev/null || true
  pkill -f "linux-wallpaperengine.*--bg" 2>/dev/null || true
  sleep 0.5
  setsid nohup "$BIN" \
    --assets-dir "$ASSETS" \
    --screen-root "$SCREEN" \
    --scaling "$SCALING" \
    --bg "$1" </dev/null >/tmp/wallpaper-switch.log 2>&1 &
  disown
  echo "Wallpaper activo: $1 ($SCREEN)"
}

case "${1:-}" in
  ""|-l|list)
    list_wallpapers
    echo "Uso: wallpaper-switch.sh [<id-steam>|<path-local>|reset]"
    ;;
  reset)
    pkill -f "linux-wallpaperengine.*--bg" 2>/dev/null || true
    systemctl --user start "$SERVICE" 2>/dev/null || true
    echo "Volviendo al wallpaper por defecto (home.nix)."
    ;;
  *)
    if [ ! -d "$WORKSHOP/$1" ] && [ ! -d "$1" ]; then
      echo "No existe: $1 (ni como id de workshop ni como ruta)" >&2
      echo "Lista de descargados:" >&2
      list_wallpapers >&2
      exit 1
    fi
    run_manual "$1"
    ;;
esac