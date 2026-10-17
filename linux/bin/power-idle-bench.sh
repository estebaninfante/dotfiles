#!/usr/bin/env bash
# power-idle-bench.sh [segundos] — mide el consumo en reposo recién arrancada.
#
# Muestrea la batería (todo el sistema) y el PPT del APU, e imprime/sumariza
# una línea en /var/log/power-idle.tsv para poder comparar entre boots y entre
# cambios de configuración (ASPM, PSR, dGPU, etc).
#
# Corre sola al arrancar (power-idle-bench.service, después de multi-user.target
# y antes de la sesión de usuario) y se puede correr a mano en cualquier momento.
#
# Uso:
#   power-idle-bench.sh            # 30 s
#   power-idle-bench.sh 60
#   power-idle-bench.sh --show     # últimas mediciones
#
# Referencia: docs/energia-laptop-82y5.md
set -uo pipefail

LOG=/var/log/power-idle.tsv
if ! { [ -e "$LOG" ] && [ -w "$LOG" ]; } && [ ! -w /var/log ]; then
  LOG="${XDG_STATE_HOME:-$HOME/.local/state}/power-idle.tsv"
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
fi

# lee un archivo privilegiado (debugfs) como root o vía sudo -n
rd() {
  cat "$1" 2>/dev/null || sudo -n cat "$1" 2>/dev/null
}

show() {
  [ -f "$LOG" ] || { echo "sin mediciones todavía ($LOG)"; return 0; }
  printf '%-19s %7s %8s %8s %8s %7s %-10s %-4s %-9s %s\n' \
    fecha uptime bat_min bat_avg bat_max ppt_avg aspm psr dgpu brillo
  awk -F'\t' '{printf "%-19s %7s %8s %8s %8s %7s %-10s %-4s %-9s %s\n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10}' "$LOG"
}

if [ "${1:-}" = "--show" ]; then show; exit 0; fi
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0; fi

dur="${1:-30}"
case "$dur" in ''|*[!0-9]*) echo "uso: $0 [segundos|--show]" >&2; exit 2 ;; esac

batt=/sys/class/power_supply/BAT0/power_now
[ -r "$batt" ] || { echo "sin BAT0 (¿solo AC?)" >&2; exit 3; }

ppt=""
for h in /sys/class/hwmon/hwmon*; do
  [ "$(cat "$h/name" 2>/dev/null)" = "amdgpu" ] && ppt="$h/power1_input"
done

tmp="$(mktemp)"; tmpp="$tmp.ppt"
trap 'rm -f "$tmp" "$tmpp"' EXIT

i=0
while [ "$i" -lt "$dur" ]; do
  b="$(cat "$batt" 2>/dev/null)"
  [ -n "$b" ] && awk -v v="$b" 'BEGIN{printf "%.3f\n", v/1000000}' >>"$tmp"
  if [ -n "$ppt" ] && [ -r "$ppt" ]; then
    awk -v v="$(cat "$ppt")" 'BEGIN{printf "%.3f\n", v/1000000}' >>"$tmpp"
  fi
  sleep 1
  i=$((i + 1))
done

pstats() {
  awk 'NR==1{mn=$1;mx=$1}{s+=$1;if($1<mn)mn=$1;if($1>mx)mx=$1}
       END{if(NR)printf "%.2f %.2f %.2f",mn,s/NR,mx; else printf "0 0 0"}' "$1"
}
read -r bmin bavg bmax <<<"$(pstats "$tmp")"
pavg=0
[ -s "$tmpp" ] && pavg="$(awk '{s+=$1}END{printf "%.2f",s/NR}' "$tmpp")"

dri=/sys/kernel/debug/dri/0000:05:00.0/eDP-2
aspm="$(sed -n 's/.*\[\([a-z]*\)\].*/\1/p' /sys/module/pcie_aspm/parameters/policy 2>/dev/null)"
psr="$(rd "$dri/psr_capability" | awk -F': ' '/Driver support/{print $2}' | cut -d' ' -f1)"
[ -z "${psr:-}" ] && psr="?"
dgpu="$(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status 2>/dev/null)"
[ -z "${dgpu:-}" ] && dgpu="?"
b="$(ls -d /sys/class/backlight/* 2>/dev/null | head -1)"
brillo="?"
[ -n "$b" ] && brillo="$(awk -v c="$(cat "$b/brightness")" -v m="$(cat "$b/max_brightness")" 'BEGIN{printf "%d%%",100*c/m}')"

uptime_s="$(cut -d. -f1 /proc/uptime)"
line="$(date '+%Y-%m-%d %H:%M:%S')	$uptime_s	$bmin	$bavg	$bmax	$pavg	$aspm	$psr	$dgpu	$brillo"
printf '%s\n' "$line" | tee -a "$LOG" 2>/dev/null || printf '%s\n' "$line"

printf 'reposo (%ss): batería min/avg/max = %s / %s / %s W — APU PPT avg = %s W (ASPM=%s PSR=%s dGPU=%s brillo=%s)\n' \
  "$dur" "$bmin" "$bavg" "$bmax" "$pavg" "$aspm" "$psr" "$dgpu" "$brillo"
