#!/usr/bin/env bash
# verify/energia.sh — chequeo determinista del estado de energía de la laptop.
#
# Solo lee; no cambia nada. Sale 0 si todo lo *gestionado* por el repo está
# donde corresponde, 1 si algo se revirtió. Los puntos que son una decisión
# (PSR, dGPU despierta, Wi-Fi power save) se reportan como AVISO.
#
# Uso:
#   scripts/verify/energia.sh          # texto
#   scripts/verify/energia.sh --quiet  # solo FAIL/AVISO
#
# Referencia: docs/energia-laptop-82y5.md
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

fails=0
warns=0

ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
warn() { warns=$((warns + 1)); printf '  AVISO %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }
info() { [ "$QUIET" = 1 ] || printf '  info  %s\n' "$*"; }

# --- fuente de energía ----------------------------------------------------
battery=1
for p in /sys/class/power_supply/*/online; do
  [ -f "$p" ] || continue
  case "$p" in */BAT*) continue ;; esac
  [ "$(cat "$p" 2>/dev/null)" = "1" ] && battery=0
done
src="batería"; [ "$battery" = 0 ] && src="AC"

pw() { cat /sys/class/power_supply/BAT0/power_now 2>/dev/null; }
p="$(pw)"
if [ -n "${p:-}" ]; then
  printf 'Energía — fuente: %s — consumo: %.2f W\n' "$src" "$(awk -v v="$p" 'BEGIN{print v/1000000}')"
else
  printf 'Energía — fuente: %s\n' "$src"
fi

# --- perfil / EPP ---------------------------------------------------------
gov="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
epp="$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)"
drv="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null)"
[ "$drv" = "amd-pstate-epp" ] && ok "driver de CPU: $drv (activo/EPP)" || warn "driver de CPU: $drv (se espera amd-pstate-epp)"
if [ "$battery" = 1 ]; then
  [ "$gov" = "powersave" ] && ok "governor: powersave" || fail "governor: $gov (en batería se espera powersave)"
  [ "$epp" = "power" ] && ok "EPP: power" || warn "EPP: $epp (en batería se espera power)"
else
  info "governor/EPP: $gov/$epp"
fi

# --- ASPM (gestionado por battery-power-guard.sh) -------------------------
aspm="$(sed -n 's/.*\[\([a-z]*\)\].*/\1/p' /sys/module/pcie_aspm/parameters/policy 2>/dev/null)"
noaspm=0
for d in 0000:05:00.0 0000:01:00.0; do
  [ -e "/sys/bus/pci/devices/$d" ] || continue
  case "$(command -v lspci >/dev/null && sudo -n lspci -vv -s "${d#0000:}" 2>/dev/null | grep -m1 'LnkCtl:' )" in
    *"ASPM L1"*|*"ASPM L0s"*) ;;
    *) noaspm=$((noaspm + 1)) ;;
  esac
done
if [ "$battery" = 1 ]; then
  [ "$aspm" = "powersave" ] && ok "ASPM: powersave" || fail "ASPM: $aspm (guard debió poner powersave)"
else
  info "ASPM: $aspm"
fi
[ "$noaspm" -gt 0 ] && warn "$noaspm link(s) de GPU sin ASPM negociado (iGPU/dGPU)"

# --- PSR del panel (decisión pendiente: dcdebugmask) ----------------------
cap="$(sudo -n cat /sys/kernel/debug/dri/0000:05:00.0/eDP-2/psr_capability 2>/dev/null)"
if [ -n "${cap:-}" ]; then
  if printf '%s' "$cap" | grep -q 'Driver support: yes'; then
    warn "PSR: habilitado — se sacó el workaround anti-freeze (dcdebugmask=0x10)? ver doc 4.2"
  else
    ok "PSR: deshabilitado a propósito (workaround de freeze, ver doc 4.2)"
  fi
fi

# --- dGPU ----------------------------------------------------------------
gpu="/sys/bus/pci/devices/0000:01:00.0"
if [ -e "$gpu" ]; then
  st="$(cat "$gpu/power/runtime_status" 2>/dev/null)"
  act="$(cat "$gpu/power/runtime_active_time" 2>/dev/null)"
  up="$(cut -d. -f1 /proc/uptime)"
  if [ "$st" = "suspended" ]; then
    ok "dGPU: suspendida"
  else
    pct="$(awk -v a="${act:-0}" -v u="${up:-1}" 'BEGIN{printf "%d", (u>0)?100*a/(u*1000):0}')"
    if [ "${pct:-0}" -ge 90 ]; then
      warn "dGPU: activa ${pct}% del uptime (~4-9 W) — ver §4.1 del doc"
    else
      info "dGPU: activa (${pct}% del uptime)"
    fi
  fi
fi

# --- USB y periféricos ---------------------------------------------------
for u in 3-1 1-2; do
  d="/sys/bus/usb/devices/$u"
  [ -e "$d" ] || continue
  c="$(cat "$d/power/control" 2>/dev/null)"
  [ "$c" = "auto" ] && ok "USB $u: auto" || warn "USB $u ($(cat "$d/product" 2>/dev/null)): $c — ~0.2-1 W (riesgoso en el teclado)"
done

# --- NMI watchdog ---------------------------------------------------------
nmi="$(cat /proc/sys/kernel/nmi_watchdog 2>/dev/null)"
if [ "$battery" = 1 ]; then
  [ "$nmi" = "0" ] && ok "NMI watchdog: off" || fail "NMI watchdog: $nmi (en batería se espera 0)"
else
  info "NMI watchdog: $nmi"
fi

# --- Wi-Fi power save (opt-in) -------------------------------------------
wl="$(ls -d /sys/class/net/wl* 2>/dev/null | head -1)"
if [ -n "$wl" ]; then
  ps="$(iw dev "$(basename "$wl")" get power_save 2>/dev/null | awk -F': ' '{print $2}')"
  if [ -f /var/lib/power-guard/wifi-powersave ]; then
    [ "$ps" = "on" ] && ok "Wi-Fi power save: on (opt-in activo)" || warn "Wi-Fi power save: off pese al flag /var/lib/power-guard/wifi-powersave"
  else
    info "Wi-Fi power save: ${ps:-?} (opt-in: touch /var/lib/power-guard/wifi-powersave)"
  fi
fi

printf '\n'
if [ "$fails" -gt 0 ]; then
  printf 'RESULTADO: %d falla(s), %d aviso(s) — correr battery-power-guard.sh\n' "$fails" "$warns"
  exit 1
fi
printf 'RESULTADO: ok (%d aviso(s))\n' "$warns"
exit 0
