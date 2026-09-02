#!/usr/bin/env bash
# Daemon: monitorea estado de tapa, suspende al cerrar si:
#   - Batería (siempre)
#   - AC + flag /run/lid-suspend-force (toggle F10 activo)
# Se ejecuta como servicio de sistema (root).

on_battery() {
  for p in /sys/class/power_supply/*/online; do
    [ -f "$p" ] || continue
    # Saltar baterías: solo importa fuente externa (ADP0, AC*, etc.)
    case "$p" in */BAT*) continue;; esac
    [ "$(cat "$p")" = "1" ] && return 1
  done
  return 0
}

LID="/proc/acpi/button/lid/LID0/state"

# Esperar a que aparezca el archivo de estado de la tapa.
while [ ! -f "$LID" ]; do sleep 2; done

# Estado inicial
lid_was_open=true
[ "$(cat "$LID" 2>/dev/null)" = "open" ] || lid_was_open=false

while true; do
  state="$(cat "$LID" 2>/dev/null || echo unknown)"

  if [ "$state" = "closed" ] && [ "$lid_was_open" = "true" ]; then
    # Tapa acaba de cerrarse
    suspend_force=false
    [ -f /run/lid-suspend-force ] && suspend_force=true

    if on_battery || [ "$suspend_force" = "true" ]; then
      sleep 1  # debounce
      /run/current-system/sw/bin/systemctl suspend
      # Tras resume, esperar a que el sistema se estabilice
      sleep 5
      state="$(cat "$LID" 2>/dev/null || echo unknown)"
    fi
  fi

  [ "$state" = "open" ] && lid_was_open=true || lid_was_open=false
  sleep 1
done
