#!/usr/bin/env bash
# Live system stats for the dashboard clock. Prints one JSON object.
#
# Everything here is read from /proc, /sys, and df — no external tooling to
# break, and one sampled CPU reading rather than a persistent sampler. The
# single sleep is the sampling window; it is deliberately short because the
# panel polls this every couple of seconds.

set -u

read_cpu() {
  awk '/^cpu / { idle=$5+$6; total=0; for (i=2;i<=NF;i++) total+=$i; print idle, total }' /proc/stat
}

read -r idle1 total1 <<<"$(read_cpu)"
sleep 0.25
read -r idle2 total2 <<<"$(read_cpu)"
dt=$((total2 - total1))
di=$((idle2 - idle1))
if ((dt > 0)); then cpu=$(((100 * (dt - di)) / dt)); else cpu=0; fi

mem_total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
mem_used=$((mem_total - mem_avail))
swap_total=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)
swap_free=$(awk '/^SwapFree:/{print $2}' /proc/meminfo)
swap_used=$((swap_total - swap_free))

read -r up _ < /proc/uptime
load=$(awk '{print $1" "$2" "$3}' /proc/loadavg)
host=$(uname -n)

read -r disk_total disk_used < <(df -k --output=size,used / | awk 'NR==2{print $1, $2}')
disk_pct=0
((disk_total > 0)) && disk_pct=$((100 * disk_used / disk_total))

# Hottest plausible reading across thermal zones and hwmon inputs. The globs
# are expanded by bash; an unmatched one is a cat error we swallow, so the
# pipeline yields nothing and the field degrades to null rather than hanging
# on a stdin read.
temp=$({ cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null
         cat /sys/class/hwmon/hwmon*/temp*_input 2>/dev/null
       } | awk '$1 >= 1000 && $1 <= 150000 { print int($1 / 1000) }' | sort -n | tail -1)

printf '{"host":"%s","cpu":%s,"load":[%s],"memUsedKb":%s,"memTotalKb":%s,"swapUsedKb":%s,"swapTotalKb":%s,"diskUsedKb":%s,"diskTotalKb":%s,"diskPct":%s,"tempC":%s,"uptimeSec":%s}\n' \
  "$host" \
  "$cpu" \
  "${load// /,}" \
  "$mem_used" "$mem_total" \
  "$swap_used" "$swap_total" \
  "$disk_used" "$disk_total" "$disk_pct" \
  "${temp:-null}" \
  "${up%.*}"
