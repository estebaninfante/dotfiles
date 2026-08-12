#!/usr/bin/env bash
# Cambia perfil de energia via power-profiles-daemon (API org.freedesktop.UPower.PowerProfiles).
# Uso: power-mode.sh [saver|balanced|performance|toggle|status]
set -euo pipefail

SVC="org.freedesktop.UPower.PowerProfiles"
OBJ="/org/freedesktop/UPower/PowerProfiles"
IFACE="org.freedesktop.UPower.PowerProfiles"

get_profile() {
  busctl get-property "$SVC" "$OBJ" "$IFACE" ActiveProfile 2>/dev/null | cut -d'"' -f2
}

set_profile() {
  busctl call "$SVC" "$OBJ" org.freedesktop.DBus.Properties Set ssv \
    "$IFACE" ActiveProfile s "$1" >/dev/null
}

ac_status() {
  for p in /sys/class/power_supply/A*/online; do
    [ -f "$p" ] && [ "$(cat "$p")" = "1" ] && { echo "AC"; return; }
  done
  echo "bateria"
}

current=$(get_profile || echo "desconocido")

case "${1:-status}" in
  saver|power-saver)   set_profile power-saver ;;
  balanced)            set_profile balanced ;;
  performance)         set_profile performance ;;
  toggle)
    if [ "$current" = "performance" ]; then
      set_profile power-saver
    else
      set_profile performance
    fi
    ;;
  status)
    echo "Fuente: $(ac_status)  Perfil: $current"
    exit 0
    ;;
  *)
    echo "Uso: power-mode.sh [saver|balanced|performance|toggle|status]" >&2
    exit 1
    ;;
esac

echo "Fuente: $(ac_status)  Perfil: $(get_profile)"
