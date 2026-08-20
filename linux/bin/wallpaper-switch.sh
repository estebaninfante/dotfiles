#!/usr/bin/env bash
# Cambia el wallpaper animado de Wallpaper Engine de forma PERMANENTE.
# Escribe ~/.config/wallpaper-current (+ scaling) y reinicia el servicio.
#   (sin args)                 : lista wallpapers de workshop descargados
#   wallpaper-switch.sh <id>   : pon ese wallpaper (persistente)
#   wallpaper-switch.sh scaling <mode> : cambia scaling (stretch|fit|fill|default)
#   wallpaper-switch.sh reset  : vuelve al wallpaper por defecto (home.nix)
# Los ids de workshop viven en steamapps/workshop/content/431960/<id>/
set -euo pipefail
WORKSHOP="$HOME/.steam/steam/steamapps/workshop/content/431960"
CFG_DIR="$HOME/.config"
ID_FILE="$CFG_DIR/wallpaper-current"
SCALING_FILE="$CFG_DIR/wallpaper-scaling"
SERVICE="linux-wallpaperengine.service"
DEFAULT_ID="2981249186"
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
restart_service() {
  systemctl --user restart "$SERVICE" 2>/dev/null || true
}
case "${1:-}" in
  ""|-l|list)
    list_wallpapers
    echo "Uso: wallpaper-switch.sh [<id-steam>|scaling <mode>|reset]"
    ;;
  scaling)
    mode="${2:-}"
    case "$mode" in
      stretch|fit|fill|default)
        echo "$mode" > "$SCALING_FILE"
        restart_service
        echo "Scaling: $mode (persistente)"
        ;;
      *)
        echo "Modes: stretch|fit|fill|default" >&2
        exit 1
        ;;
    esac
    ;;
  reset)
    echo "$DEFAULT_ID" > "$ID_FILE"
    echo "fill" > "$SCALING_FILE"
    restart_service
    echo "Wallpaper por defecto restaurado ($DEFAULT_ID)."
    ;;
  *)
    if [ ! -d "$WORKSHOP/$1" ] && [ ! -d "$1" ]; then
      echo "No existe: $1 (ni como id de workshop ni como ruta)" >&2
      echo "Lista de descargados:" >&2
      list_wallpapers >&2
      exit 1
    fi
    echo "$1" > "$ID_FILE"
    restart_service
    echo "Wallpaper activo (persistente): $1"
    ;;
esac
