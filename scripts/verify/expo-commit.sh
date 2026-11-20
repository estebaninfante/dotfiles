#!/usr/bin/env bash
# verifica base/expo-commit.lua sin abrir el escritorio (plugin de mentira).
#
# El caso: ir con SUPER+<n> a un workspace SIN VENTANAS. La grilla de hyprexpo
# es dinámica (sólo espacios con ventanas), así que ese destino no tiene tile:
# el plugin falla, no cierra la grilla y el zoom del "peek" quedaba pegado
# (ventanas ~1.3x y colgando fuera de la pantalla). Ver expo-commit.lua.
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

exec lua "$HERE/expo-commit.lua"
