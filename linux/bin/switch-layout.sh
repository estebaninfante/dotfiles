#!/bin/bash
# switch-layout.sh <layout_index|next|prev>
# 0 = dvk_prog, 1 = es, 2 = us
#
# Aplica el layout a TODOS los teclados de Hyprland (no solo al físico): un
# cliente de Sunshine/Moonlight inyecta posiciones QWERTY por un teclado
# virtual, y ese es el que se queda en dvk_prog si no se toca también.
set -uo pipefail

LAYOUT="${1:-2}"

# Sunshine (y otros servicios) corren sin el entorno del compositor: sin
# HYPRLAND_INSTANCE_SIGNATURE hyprctl no conecta. Se busca la instancia viva.
SIG="${HYPRLAND_INSTANCE_SIGNATURE:-}"
hypr() {
    if [ -n "$SIG" ]; then
        HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@"
    else
        hyprctl "$@"
    fi
}

if ! hypr monitors -j >/dev/null 2>&1; then
    for d in $(ls -1dt /run/user/"$(id -u)"/hypr/*/ 2>/dev/null); do
        SIG="$(basename "$d")"
        if hypr monitors -j >/dev/null 2>&1; then break; fi
        SIG=""
    done
fi

hypr switchxkblayout all "$LAYOUT" >/dev/null 2>&1
