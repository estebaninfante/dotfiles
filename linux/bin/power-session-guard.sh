#!/usr/bin/env bash
# Guard de sesion (corre como USUARIO via power-session-guard.service).
#
# Al cambiar la fuente de alimentacion re-evalua en caliente lo unico que
# depende del estado de bateria (monitors.lua -> 60Hz/120Hz, looknfeel.lua ->
# blur) con `hyprctl eval`, sin un `hyprctl reload` completo (tarda ~1.5s y
# deja el panel en negro todo ese rato). El cambio de modo del panel, que es el
# que realmente parpadea, se hace detras de un fundido a negro (`pantalla-fade`)
# para que se sienta como un apagado lento y no como un golpe. Despues
# arranca/para Sunshine.
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

# Modo ahorro extremo: existe y se sale solo al enchufar el cargador.
# El script es del usuario (maneja systemd --user, brillo y shell.json).
EXTREME_FLAG="$HOME/.local/state/power-extreme/on"
if [ -f "$EXTREME_FLAG" ] && ! on_battery; then
  log "AC conectado: saliendo del modo ahorro extremo"
  "$HOME/.local/bin/power-extreme.sh" off >/dev/null 2>&1 || log "no se pudo salir del modo extremo"
fi

if ! wait_hypr; then
  log "Hyprland no responde; nada que hacer"
  exit 0
fi

desired=performance
low_power && desired=save

# Re-aplica en caliente el modo del panel y el blur del estado de energia
# actual, detras de un fundido a negro. Si los helpers de la config no existen
# (config vieja) o `pantalla-fade` no esta, cae al reload completo de siempre.
aplicar_modo() {
  local code="omarchy.apply_power_monitors(); omarchy.apply_power_blur()"
  if command -v pantalla-fade >/dev/null 2>&1; then
    pantalla-fade cover -- hyprctl eval "$code" >/dev/null 2>&1 && return 0
  fi
  hyprctl eval "$code" >/dev/null 2>&1 && return 0
  hyprctl reload >/dev/null 2>&1 || true
}

state_file="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/power-session-guard.mode"
applied="$(cat "$state_file" 2>/dev/null || true)"

if [ "$applied" = "$desired" ]; then
  log "estado '$desired' sin cambios; no recargo Hyprland"
else
  # El reload re-aplica el modo del panel (60Hz en ahorro, 120Hz en
  # rendimiento) y eso deja el OLED en negro unas décimas: se hace detras de
  # una cortina que baja y sube con fundido (`pantalla-fade`), en vez de que la
  # pantalla se apague de golpe. Si el shell no responde, el reload ocurre igual.
  if [ "$desired" = save ]; then
    log "ahorro (bateria o power-saver): recargando config de ahorro"
    aplicar_modo
    notify -u low -g "󰂄" --app-name Energia \
      "Modo ahorro" "60Hz, sin blur, Sunshine off" 2>/dev/null || true
  else
    log "AC/rendimiento: recargando config completa"
    aplicar_modo
    sleep 4
    notify -u low -g "󰂄" --app-name Energia \
      "Rendimiento completo" "120Hz, Sunshine on" 2>/dev/null || true
  fi
  printf '%s\n' "$desired" >"$state_file" 2>/dev/null || true
fi

if [ "$desired" = save ]; then
  systemctl --user stop sunshine.service >/dev/null 2>&1 || true
else
  systemctl --user start sunshine.service >/dev/null 2>&1 || true
fi
