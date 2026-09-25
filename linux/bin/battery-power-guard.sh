#!/usr/bin/env bash
# Guard de energia por fuente de alimentacion (corre como ROOT).
#
# Disparadores:
#   - udev: change de ADP0 -> systemctl --no-block start battery-power-guard.service
#     (regla /etc/udev/rules.d/99-power-source.rules)
#   - systemd: WantedBy=multi-user.target (aplica el estado tambien en cada boot)
#
# BATERIA: power-saver + dGPU runtime-PM + syncthing off + brillo <=50%.
# AC:      performance + syncthing on + brillo restaurado.
# Despues dispara la guard de sesion de usuario (refresco/blur/anims/sunshine),
# que vive en power-session-guard.sh porque necesita hyprctl.
#
# NO usa gpu-mode.sh battery: su ac_off() apaga la dGPU por ACPI una sola vez
# (sin metodo _ON) y dejaria la GPU inutil hasta reiniciar.
set -uo pipefail

BIN_DIR="/home/eztvn/dotfiles/linux/bin"
BRIGHT_SAVE="/var/lib/power-guard/brightness-ac"
USER_NAME="eztvn"
USER_RT="/run/user/1000"

log() { logger -t battery-power-guard -- "$*"; echo "$*"; }

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

gpu_pci() {
  local v
  for v in /sys/bus/pci/devices/*/vendor; do
    [ -f "$v" ] || continue
    [ "$(cat "$v" 2>/dev/null)" = "0x10de" ] && basename "$(dirname "$v")" && return 0
  done
  return 1
}

# dGPU en runtime-PM (auto) sin persistencia: se enciende solo cuando hace falta.
gpu_powersave() {
  local pci ctrl
  pci="$(gpu_pci)" || return 0
  ctrl="/sys/bus/pci/devices/$pci/power/control"
  [ -w "$ctrl" ] || return 0
  echo auto >"$ctrl" 2>/dev/null || true
  command -v nvidia-smi >/dev/null && nvidia-smi -pm 0 >/dev/null 2>&1 || true
}

backlight_dir() { ls -d /sys/class/backlight/* 2>/dev/null | head -1; }

bright_record() {
  local b cur
  b="$(backlight_dir)"; [ -n "$b" ] || return 0
  cur="$(cat "$b/brightness" 2>/dev/null)" || return 0
  mkdir -p "$(dirname "$BRIGHT_SAVE")"
  echo "$cur" >"$BRIGHT_SAVE" 2>/dev/null || true
}

# Cap al 50%: guarda el valor previo (si no hay) y baja si esta por encima.
bright_cap_half() {
  local b cur max cap
  b="$(backlight_dir)"; [ -n "$b" ] || return 0
  max="$(cat "$b/max_brightness" 2>/dev/null)"; [ -n "$max" ] || return 0
  cur="$(cat "$b/brightness" 2>/dev/null)"; [ -n "$cur" ] || return 0
  mkdir -p "$(dirname "$BRIGHT_SAVE")"
  [ -f "$BRIGHT_SAVE" ] || echo "$cur" >"$BRIGHT_SAVE" 2>/dev/null || true
  cap=$((max / 2))
  if [ "$cur" -gt "$cap" ]; then
    echo "$cap" >"$b/brightness" 2>/dev/null || true
  fi
}

bright_restore() {
  local b val
  b="$(backlight_dir)"; [ -n "$b" ] || return 0
  [ -f "$BRIGHT_SAVE" ] || return 0
  val="$(cat "$BRIGHT_SAVE")" || return 0
  echo "$val" >"$b/brightness" 2>/dev/null || true
}

session_trigger() {
  [ -S "$USER_RT/bus" ] || return 0
  runuser -u "$USER_NAME" -- env XDG_RUNTIME_DIR="$USER_RT" \
    systemctl --user restart power-session-guard.service >/dev/null 2>&1 || true
}

if low_power; then
  if on_battery; then
    log "bateria: power-saver + dGPU auto + syncthing off + brillo<=50%"
    "$BIN_DIR/power-mode.sh" power-saver >/dev/null 2>&1 || true
  else
    log "power-saver (AC): dGPU auto + syncthing off + brillo<=50%"
  fi
  gpu_powersave
  systemctl stop syncthing.service >/dev/null 2>&1 || true
  bright_cap_half
else
  log "AC/rendimiento: syncthing on + brillo restaurado"
  gpu_powersave
  [ -f /tmp/syncthing-manual-off ] || systemctl start syncthing.service >/dev/null 2>&1 || true
  bright_record
  bright_restore
fi

session_trigger
