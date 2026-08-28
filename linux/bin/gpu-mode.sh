#!/usr/bin/env bash
# Controla la GPU NVIDIA via Runtime PM (laptop híbrida AMD + RTX).
#   battery : GPU en D3cold cuando está inactiva
#   gaming  : GPU forzada activa + persistence mode → lista para jugar
#   enable  : arranca especialización NVIDIA y reinicia
#   disable : vuelve al perfil AMD y reinicia
#   guard   : automático por fuente de energía (batería → battery, AC → sin cambios)
# Uso: gpu-mode.sh [battery|gaming|toggle|guard|status]
set -euo pipefail

GPU_PCI="0000:01:00.0"
CTRL="/sys/bus/pci/devices/$GPU_PCI/power/control"
STATE="/sys/bus/pci/devices/$GPU_PCI/power/runtime_status"
ACPI="/proc/acpi/call"
OFFFLAG="/tmp/gpu-acpi-off"

# Métodos ACPI _OFF a probar (corte físico del rail de la dGPU).
# En esta laptop (Legion Slim 5 82Y5) el PowerResource de la dGPU es
# \_SB.PCI0.GPP0.PG00 (ver SSDT4: _PR0 de PEGP → PG00).
ACPI_METHODS=(
  '\_SB.PCI0.GPP0.PG00._OFF'
  '\_SB.PCI0.PEG0.PG00._OFF'
  '\_SB.PCI0.GPP0.PEGP._OFF'
)

find_gpu() {
  local dev
  for dev in /sys/bus/pci/devices/*/vendor; do
    if [ "$(cat "$dev" 2>/dev/null)" = "0x10de" ]; then
      GPU_PCI="$(basename "$(dirname "$dev")")"
      CTRL="/sys/bus/pci/devices/$GPU_PCI/power/control"
      STATE="/sys/bus/pci/devices/$GPU_PCI/power/runtime_status"
      return 0
    fi
  done
  return 1
}

ac_status() {
  for p in /sys/class/power_supply/AC*/online; do
    [ -f "$p" ] && [ "$(cat "$p")" = "1" ] && { echo "AC"; return; }
  done
  echo "bateria"
}

driver_active() {
  [ -e "/sys/bus/pci/devices/$GPU_PCI/driver" ] &&
    [ "$(basename "$(readlink "/sys/bus/pci/devices/$GPU_PCI/driver")")" = "nvidia" ]
}

switch_profile() {
  local profile="$1"
  local switcher
  if [ "$profile" = "nvidia" ]; then
    switcher="/run/current-system/specialisation/nvidia/bin/switch-to-configuration"
  else
    switcher="/run/current-system/bin/switch-to-configuration"
  fi
  if [ ! -x "$switcher" ]; then
    echo "Perfil NVIDIA no disponible: ejecuta rebuild primero" >&2
    exit 1
  fi
  if [ "$(id -u)" = "0" ]; then
    "$switcher" boot
  else
    sudo "$switcher" boot
  fi
  notify-send "GPU NVIDIA" "Perfil $profile seleccionado; reiniciando" 2>/dev/null || true
  systemctl reboot
}

current_mode() {
  [ "$(cat "$CTRL")" = "on" ] && echo "gaming" || echo "battery"
}

set_mode() { # $1 = on|auto, $2 = persistence 0|1
  if [ "$(id -u)" = "0" ]; then
    tee "$CTRL" <<<"$1" >/dev/null
    nvidia-smi -pm "$2" >/dev/null 2>&1 || true
  else
    sudo tee "$CTRL" <<<"$1" >/dev/null
    sudo nvidia-smi -pm "$2" >/dev/null 2>&1 || true
  fi
}

ac_off() {
  if [ ! -e "$ACPI" ]; then
    echo "acpi_call no disponible (rebuild requerido)" >&2
    return 1
  fi
  local m ret
  for m in "${ACPI_METHODS[@]}"; do
    echo "$m" | sudo tee "$ACPI" >/dev/null 2>&1 || continue
    ret=$(sudo cat "$ACPI" 2>/dev/null | tr -d '\0' || true)
    if [ "${ret#*Error}" = "$ret" ]; then
      echo "$m" > "$OFFFLAG" 2>/dev/null || true
      echo "ACPI _OFF aplicado: $m"
      return 0
    fi
  done
  echo "Ningún método ACPI _OFF funcionó" >&2
  return 1
}

if ! find_gpu; then
  echo "GPU NVIDIA no encontrada"
  exit 1
fi

mode="disabled"
if driver_active; then
  mode=$(current_mode)
fi

case "${1:-status}" in
  enable)
    switch_profile nvidia
    ;;
  disable)
    switch_profile amd
    ;;
  battery)
    if [ "$mode" = "disabled" ]; then
      ac_off || true
      exit 0
    fi
    set_mode auto 0
    ac_off || true
    ;;
  off)
    if [ "$mode" != "disabled" ]; then
      echo "Driver NVIDIA activo; no se puede apagar por ACPI" >&2
      exit 1
    fi
    ac_off
    ;;
  gaming)
    if [ "$mode" = "disabled" ]; then
      echo "NVIDIA desactivada; usa gpu-mode.sh enable y reinicia" >&2
      exit 1
    fi
    set_mode on 1
    ;;
  guard)
    # Automático: batería → battery (guarda); AC → no tocar (el gaming lo pide el usuario manualmente)
    if [ "$(ac_status)" = "bateria" ]; then
      set_mode auto 0
      notify-send -u low "GPU NVIDIA" "Batería: GPU suspendida (ahorro energía)" 2>/dev/null || true
    fi
    ;;
  toggle)
    if [ "$mode" = "disabled" ]; then
      switch_profile nvidia
    elif [ "$mode" = "gaming" ]; then
      set_mode auto 0
    else
      set_mode on 1
    fi
    ;;
  status)
    state="desactivada"
    driver_active && state=$(cat "$STATE")
    acpi="on"
    [ -f "$OFFFLAG" ] && acpi="off"
    echo "GPU: $state  ACPI: $acpi  Modo: $mode  Fuente: $(ac_status)"
    exit 0
    ;;
  *)
    echo "Uso: gpu-mode.sh [enable|disable|battery|gaming|toggle|guard|status]" >&2
    exit 1
    ;;
esac

echo "GPU: $(cat "$STATE")  Modo: $(current_mode)  Fuente: $(ac_status)"
