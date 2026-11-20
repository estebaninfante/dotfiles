#!/usr/bin/env bash
# verifica base/expo-tile.lua sin abrir el escritorio.
#
# El caso: ir con SUPER+<tecla> a un workspace SIN VENTANAS. La grilla de
# hyprexpo es dinámica (sólo espacios con ventanas), así que ese destino no tiene
# tile: el vuelo no aterriza, el plugin no lo avisa y la grilla quedaba abierta a
# mitad del zoom del peek (ventanas ~1.3x y colgando fuera de la pantalla).
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

exec lua "$HERE/expo-tile.lua"
