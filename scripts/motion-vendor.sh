#!/usr/bin/env bash
# Copia el motor de movimiento (fuente: ~/.config/omarchy/motion) dentro de los
# consumidores que lo necesitan.
#
# Por qué copiar y no symlink ni import hacia arriba: Quickshell resuelve los
# imports QML dentro del root de la config y rechaza cualquier ruta que suba de
# directorio ("Reveal is not a type"). Un subdirectorio sí funciona, así que el
# motor se vendoriza; este script es el único que lo copia, y verify/motion.sh
# falla si una copia se desvía.
#
# Uso: motion-vendor.sh [destino ...]
#   sin argumentos: plugins/eztvn.motion/motion y bar/modules/motion
set -euo pipefail
SRC="$HOME/.config/omarchy/motion"
[[ -f "$SRC/motion.json" ]] || { echo "falta el motor en $SRC" >&2; exit 1; }

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
  targets=("$HOME/.config/omarchy/plugins/eztvn.motion/motion"
           "$HOME/.config/omarchy/bar/modules/motion")
fi

for dst in "${targets[@]}"; do
  mkdir -p "$dst"
  # Sólo lo que el motor necesita en runtime; nada de tests ni docs.
  for f in motion.json qmldir Tokens.qml Reveal.qml Stagger.qml Morph.qml Frames.qml Motion.js; do
    cp -f "$SRC/$f" "$dst/$f"
  done
  echo "ok $dst"
done
