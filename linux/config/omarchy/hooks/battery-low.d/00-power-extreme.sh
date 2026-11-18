#!/bin/bash
# Hook de batería baja de Omarchy: a <=10 % entra solo el ahorro extremo.
# Recibe el porcentaje como $1 (omarchy-battery-low). El modo se sale solo al
# enchufar el cargador. Para desactivar este automatismo: borrar este archivo
# (vive en ~/dotfiles/linux/config/omarchy/hooks/battery-low.d/).
#
# Ver docs/energia-laptop-82y5.md §8.
#
# Gracia de 60 s: un corte momentáneo del cargador (cable flojo, zapatilla) pasa
# por acá igual, con la batería ya baja, y entrar y salir del modo en 15 s mata y
# revive media sesión. Se espera, se revalida (corriente + nivel) y recién ahí
# se entra. Así el 2026-11-18 14:23 no se vuelve a repetir.

level="${1:-100}"
[[ "$level" =~ ^[0-9]+$ ]] || exit 0
(( level <= 10 )) || exit 0

GRACIA="${XDG_RUNTIME_DIR:-/tmp}/power-extreme-gracia"
# Una espera por vez: el hook se dispara varias veces mientras baja el nivel.
[ -e "$GRACIA" ] && exit 0
: >"$GRACIA"

(
  sleep 60
  rm -f "$GRACIA"

  # ¿Volvió la corriente? Entonces fue un parpadeo, no una emergencia.
  for p in /sys/class/power_supply/*/online; do
    [ -f "$p" ] || continue
    case "$p" in */BAT*) continue ;; esac
    [ "$(cat "$p" 2>/dev/null)" = "1" ] && exit 0
  done

  # ¿Sigue baja? Si subió, tampoco.
  cap="$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | sort -n | head -1)"
  [[ "$cap" =~ ^[0-9]+$ ]] || cap=100
  (( cap <= 10 )) || exit 0

  exec "$HOME/.local/bin/power-extreme.sh" on --auto
) >/dev/null 2>&1 &
