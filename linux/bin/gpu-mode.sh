#!/usr/bin/env bash
# Controla la GPU NVIDIA via Runtime PM (laptop híbrida AMD + RTX).
#   battery : GPU en D3cold cuando está inactiva → máximo ahorro de batería
#   gaming  : GPU forzada activa + persistence mode → lista para jugar
# Uso: gpu-mode.sh [battery|gaming|toggle|status]
set -euo pipefail

GPU_PCI="0000:01:00.0"
CTRL="/sys/bus/pci/devices/$GPU_PCI/power/control"
STATE="/sys/bus/pci/devices/$GPU_PCI/power/runtime_status"

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

current_mode() {
  [ "$(cat "$CTRL")" = "on" ] && echo "gaming" || echo "battery"
}

set_mode() { # $1 = on|auto, $2 = persistence 0|1
  sudo tee "$CTRL" <<<"$1" >/dev/null
  nvidia-smi -pm "$2" >/dev/null 2>&1 || true
}

if ! find_gpu; then
  echo "GPU NVIDIA no encontrada"
  exit 1
fi

mode=$(current_mode)

case "${1:-status}" in
  battery)
    set_mode auto 0
    ;;
  gaming)
    set_mode on 1
    ;;
  toggle)
    if [ "$mode" = "gaming" ]; then
      set_mode auto 0
    else
      set_mode on 1
    fi
    ;;
  status)
    echo "GPU: $(cat "$STATE")  Modo: $mode  Fuente: $(ac_status)"
    exit 0
    ;;
  *)
    echo "Uso: gpu-mode.sh [battery|gaming|toggle|status]" >&2
    exit 1
    ;;
esac

echo "GPU: $(cat "$STATE")  Modo: $(current_mode)  Fuente: $(ac_status)"