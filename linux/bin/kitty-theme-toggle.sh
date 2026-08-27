#!/usr/bin/env bash
# Toggle tema kitty claro↔oscuro (legibilidad día/noche).
# Edita active-theme.conf (symlink al repo); kitty recarga sola al detectar cambio.
set -euo pipefail

KITTY_DIR="$HOME/dotfiles/linux/config/kitty"
ACTIVE="$KITTY_DIR/active-theme.conf"

current() {
    grep -m1 '^background' "$ACTIVE" | awk '{print $2}'
}

target="$1"
case "$target" in
    light|dark) ;;  # explícito: apunta al nombre de archivo destino
    toggle|"")
        cur=$(current)
        case "$cur" in
            #fd*|#f9*|#f5*) target=dark ;;   # fondos claros → ir a oscuro
            *) target=light ;;
        esac
        ;;
    *)
        echo "uso: kitty-theme-toggle.sh [light|dark|toggle]" >&2
        exit 1
        ;;
esac

ln -sfn "theme-$target.conf" "$ACTIVE"
echo "kitty theme: $target"
