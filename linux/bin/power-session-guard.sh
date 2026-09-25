#!/usr/bin/env bash
# Guard de sesion (corre como USUARIO via power-session-guard.service).
#
# Al cambiar la fuente de alimentacion, recarga Hyprland para que su config
# re-evalue el estado de bateria (monitors.lua -> 60Hz / preferred,
# hyprland.lua -> blur y animaciones off) y arranca/para Sunshine.
#
# Sunshine: nunca via graphical-session.target puro (con linger arranca antes
# del compositor y cuelga el login). Aqui se espera a que hyprctl responda
# antes de tocarlo.
set -uo pipefail

log() { logger -t power-session-guard -- "$*"; }

on_battery() {
  for p in /sys/class/power_supply/*/online; do
    [ -f "$p" ] || continue
    case "$p" in */BAT*) continue ;; esac
    [ "$(cat "$p")" = "1" ] && return 1
  done
  return 0
}

# Perfil activo de power-profiles-daemon (D-Bus). power-saver = ahorro total.
power_saver() {
  local v
  v="$(busctl get-property org.freedesktop.UPower.PowerProfiles \
      /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles \
      ActiveProfile 2>/dev/null | cut -d'"' -f2)"
  [ "$v" = "power-saver" ]
}

# Modo ahorro: bateria O perfil power-saver (aunque haya AC).
low_power() {
  on_battery || power_saver
}

# hyprctl necesita HYPRLAND_INSTANCE_SIGNATURE. La mayoria de las veces el
# user manager ya la tiene (UWSM), pero al arrancar la sesion puede no estar
# lista: se reintenta probando cada instancia viva.
hypr_ready() {
  if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && hyprctl version >/dev/null 2>&1; then
    return 0
  fi
  local d
  for d in $(ls -t /run/user/"$(id -u)"/hypr 2>/dev/null); do
    if HYPRLAND_INSTANCE_SIGNATURE="$d" hyprctl version >/dev/null 2>&1; then
      export HYPRLAND_INSTANCE_SIGNATURE="$d"
      return 0
    fi
  done
  return 1
}

wait_hypr() {
  local i
  for i in $(seq 1 15); do
    hypr_ready && return 0
    sleep 2
  done
  return 1
}

if ! wait_hypr; then
  log "Hyprland no responde; nada que hacer"
  exit 0
fi

if low_power; then
  log "ahorro (bateria o power-saver): recargando config de ahorro"
  hyprctl reload >/dev/null 2>&1 || true
  systemctl --user stop sunshine.service >/dev/null 2>&1 || true
  notify-send -u low -a "Energia" "Modo ahorro: 60Hz, sin blur, Sunshine off" 2>/dev/null || true
else
  log "AC/rendimiento: recargando config completa"
  hyprctl reload >/dev/null 2>&1 || true
  sleep 4
  systemctl --user start sunshine.service >/dev/null 2>&1 || true
  notify-send -u low -a "Energia" "Rendimiento completo: 120Hz, Sunshine on" 2>/dev/null || true
fi
