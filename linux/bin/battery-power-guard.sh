#!/usr/bin/env bash
# Guard de energia por fuente de alimentacion (corre como ROOT).
#
# Disparadores:
#   - udev: change de ADP0 -> systemctl --no-block start battery-power-guard.service
#     (regla /etc/udev/rules.d/99-power-source.rules)
#   - systemd: WantedBy=multi-user.target (aplica el estado tambien en cada boot)
#
# BATERIA: power-saver + dGPU runtime-PM + syncthing off + brillo <=50%
#          + ASPM=powersave + lector SD suspendido + NMI watchdog off.
# AC:      performance + syncthing on + brillo restaurado + ASPM=default
#          + NMI watchdog on.
# Despues dispara la guard de sesion de usuario (refresco/blur/anims/sunshine),
# que vive en power-session-guard.sh porque necesita hyprctl.
#
# Ver docs/energia-laptop-82y5.md y scripts/verify/energia.sh.
#
# NO usa gpu-mode.sh battery: su ac_off() apaga la dGPU por ACPI una sola vez
# (sin metodo _ON) y dejaria la GPU inutil hasta reiniciar.
set -uo pipefail

BIN_DIR="/home/eztvn/dotfiles/linux/bin"
BRIGHT_SAVE="/var/lib/power-guard/brightness-ac"
GUARD_DIR="/var/lib/power-guard"
USER_NAME="eztvn"
USER_RT="/run/user/1000"
# Modo ahorro extremo (power-extreme.sh): cuando está activo, ese script manda
# sobre brillo y servicios; acá solo se respeta (wifi powersave forzado, no se
# toca el brillo).
EXTREME_FLAG="/home/$USER_NAME/.local/state/power-extreme/on"

log() { logger -t battery-power-guard -- "$*"; echo "$*"; }

extreme() { [ -f "$EXTREME_FLAG" ]; }

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

# --- tunables de kernel gestionados en caliente ---------------------------
# No hay servicio aparte: se aplican aca en cada boot y en cada cambio de
# fuente de alimentacion. Cualquier valor que falle se ignora (set -u).

# ASPM: los links de la iGPU y la dGPU quedan sin ASPM con la politica
# 'default'. En bateria conviene 'powersave' (L1/L1.2); en AC se vuelve a
# 'default' por si algun dispositivo se queja del L1 a maxima carga.
aspm_policy() {
  local f=/sys/module/pcie_aspm/parameters/policy
  [ -w "$f" ] || return 0
  echo "$1" >"$f" 2>/dev/null || true
}

# El lector de SD (clase PCI 0x0805) NO se puede suspender por runtime-PM:
# sdhci-pci no expone autosuspend_delay_ms y runtime_suspended_time queda en 0.
# Si algun dia importa (~0.3 W) la unica via es unbind/remove del controlador;
# no se hace automatico porque rompe el lector de SD.
# NMI watchdog: una NMI periodica por CPU que impide C-states profundos.
nmi_watchdog() {
  case "$1" in
    off) echo 0 >/proc/sys/kernel/nmi_watchdog 2>/dev/null || true ;;
    on)  echo 1 >/proc/sys/kernel/nmi_watchdog 2>/dev/null || true ;;
  esac
}

# Wi-Fi power save (ahorra ~0.3-1 W): OPT-IN, porque agrega picos de latencia
# de 20-300 ms en links ociosos y eso molesta a lan-mouse/voz. Habilitar con
#   sudo touch /var/lib/power-guard/wifi-powersave
# (el modo ahorro extremo lo fuerza aunque no esté el archivo).
wifi_powersave() {
  command -v iw >/dev/null 2>&1 || return 0
  local i
  for i in /sys/class/net/wl*; do
    [ -d "$i" ] || continue
    iw dev "$(basename "$i")" set power_save "$1" >/dev/null 2>&1 || true
  done
}

# --- carga y noche (solo AC) -----------------------------------------------
# La carga rapida ("Fast", ~100 W hacia la bateria) es lo que calienta la
# laptop al enchufarla. Por defecto se carga en "Standard"; de dia se puede
# volver a Fast con  sudo touch /var/lib/power-guard/fast-charge
# De noche (NIGHT_START..NIGHT_END) ademas: power-saver + sin boost de CPU.
# El timer battery-power-guard-night.timer reaplica esto a esas horas.
NIGHT_START=21
NIGHT_END=7
NIGHT_FLAG="$GUARD_DIR/night-saver"

is_night() {
  local h
  h=$((10#$(date +%H)))
  [ "$h" -ge "$NIGHT_START" ] || [ "$h" -lt "$NIGHT_END" ]
}

charge_type() {
  local f=/sys/class/power_supply/BAT0/charge_types
  [ -w "$f" ] || return 0
  echo "$1" >"$f" 2>/dev/null || true
}

cpu_boost() {
  local f=/sys/devices/system/cpu/cpufreq/boost
  [ -w "$f" ] || return 0
  echo "$1" >"$f" 2>/dev/null || true
}

charge_policy() {
  mkdir -p "$GUARD_DIR"
  if is_night; then
    charge_type Standard
    # Solo se fuerza power-saver si no lo estaba; el flag permite deshacerlo
    # en la manana sin pisar un power-saver puesto a mano. Va ANTES de apagar
    # el boost: PPD escribe policy*/boost y falla (EINVAL) con el global en 0.
    if ! power_saver; then
      cpu_boost 1
      "$BIN_DIR/power-mode.sh" power-saver >/dev/null 2>&1 && touch "$NIGHT_FLAG"
    fi
    cpu_boost 0
    log "noche (AC): carga Standard + sin boost + power-saver"
  else
    if [ -f "$GUARD_DIR/fast-charge" ]; then
      charge_type Fast
    else
      charge_type Standard
    fi
    cpu_boost 1
    if [ -f "$NIGHT_FLAG" ]; then
      power_saver && "$BIN_DIR/power-mode.sh" balanced >/dev/null 2>&1 || true
      rm -f "$NIGHT_FLAG"
    fi
  fi
}

session_trigger() {
  [ -S "$USER_RT/bus" ] || return 0
  runuser -u "$USER_NAME" -- env XDG_RUNTIME_DIR="$USER_RT" \
    systemctl --user restart power-session-guard.service >/dev/null 2>&1 || true
  runuser -u "$USER_NAME" -- env XDG_RUNTIME_DIR="$USER_RT" \
    systemctl --user --no-block start wallpaper-power-guard.service >/dev/null 2>&1 || true
}

if on_battery; then
  # En bateria manda power-saver; solo se deshace lo nocturno de dia.
  is_night || { cpu_boost 1; rm -f "$NIGHT_FLAG"; }
else
  charge_policy
fi

if low_power; then
  if on_battery; then
    log "bateria: power-saver + dGPU auto + syncthing off + ASPM powersave"
    "$BIN_DIR/power-mode.sh" power-saver >/dev/null 2>&1 || true
  else
    log "power-saver (AC): dGPU auto + syncthing off + ASPM powersave"
  fi
  gpu_powersave
  aspm_policy powersave
  nmi_watchdog off
  # En modo extremo el Wi-Fi power save ya no es opt-in: es parte del ahorro.
  if [ -f "$GUARD_DIR/wifi-powersave" ] || extreme; then
    wifi_powersave on
  fi
  systemctl stop syncthing.service >/dev/null 2>&1 || true
  if extreme; then
    log "modo extremo activo: el brillo lo maneja power-extreme.sh"
  else
    bright_cap_half
  fi
else
  log "AC/rendimiento: syncthing on + brillo restaurado + ASPM default"
  gpu_powersave
  aspm_policy default
  nmi_watchdog on
  wifi_powersave off
  [ -f /tmp/syncthing-manual-off ] || systemctl start syncthing.service >/dev/null 2>&1 || true
  if extreme; then
    log "modo extremo activo: no se toca el brillo"
  else
    bright_record
    bright_restore
  fi
fi

session_trigger
