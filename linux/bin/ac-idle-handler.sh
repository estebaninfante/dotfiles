#!/usr/bin/env bash
# Triggered by udev on AC power changes.
# Inhibits idle suspend (logind IdleAction) when on AC.
# Removes inhibitor when on battery.

on_battery() {
  for p in /sys/class/power_supply/*/online; do
    [ -f "$p" ] || continue
    case "$p" in */BAT*) continue;; esac
    [ "$(cat "$p")" = "1" ] && return 1
  done
  return 0
}

if on_battery; then
  /run/current-system/sw/bin/systemctl stop ac-idle-inhibit.service 2>/dev/null || true
else
  /run/current-system/sw/bin/systemctl start ac-idle-inhibit.service 2>/dev/null || true
fi
