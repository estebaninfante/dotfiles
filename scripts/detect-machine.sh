#!/usr/bin/env bash
# ── detect-machine.sh ──
# Detecta si la maquina es 'laptop' o 'desktop' a partir del HARDWARE real
# (DMI chassis_type, bateria, backlight). NO lee ~/.config/machine-type.
#
# Uso:
#   bash detect-machine.sh          # imprime: laptop | desktop
#   MACHINE=$(bash detect-machine.sh)
#
# Motivo: en fresh install NO se puede confiar en archivos previos ni en
# defaults de "laptop" — la desktop configurada como laptop fue exactamente
# el bug que este script previene.
set -uo pipefail

# ── 1. DMI chassis_type (mas fiable) ──
# Valores SMBIOS relevantes:
#   3=Desktop, 4=Low Profile, 5=Pizza Box, 6=Mini Tower, 7=Tower,
#   15=Space-saving, 16=Lunch Box, 17=Main Server, 18=Expansion
#   8=Portable, 9=Laptop, 10=Notebook, 14=Sub Notebook, 31=Convertible, 32=Detachable
CHASSIS="$(cat /sys/class/dmi/id/chassis_type 2>/dev/null | tr -d '[:space:]' || true)"
case "$CHASSIS" in
  3|4|5|6|7|15|16|17|18)
    echo "desktop"
    exit 0
    ;;
  8|9|10|14|31|32)
    echo "laptop"
    exit 0
    ;;
esac

# ── 2. Bateria presente → laptop ──
if grep -qi '^BAT' /sys/class/power_supply/*/type 2>/dev/null; then
  echo "laptop"
  exit 0
fi

# ── 3. Backlight portable (acpi_video0, intel_backlight, amdgpu_bl) → laptop ──
if ls /sys/class/backlight/ >/dev/null 2>&1 && [ -n "$(ls -A /sys/class/backlight/ 2>/dev/null)" ]; then
  echo "laptop"
  exit 0
fi

# ── 4. Fallback: sin señales de laptop → desktop ──
echo "desktop"
exit 0
