#!/bin/bash
# Hook de batería baja de Omarchy: a <=10 % entra solo el ahorro extremo.
# Recibe el porcentaje como $1 (omarchy-battery-low). El modo se sale solo al
# enchufar el cargador. Para desactivar este automatismo: borrar este archivo
# (vive en ~/dotfiles/linux/config/omarchy/hooks/battery-low.d/).
#
# Ver docs/energia-laptop-82y5.md §8.

level="${1:-100}"
[[ "$level" =~ ^[0-9]+$ ]] || exit 0
(( level <= 10 )) || exit 0

exec "$HOME/.local/bin/power-extreme.sh" on --auto
