#!/usr/bin/env bash

set -u

LOG_DIR="$HOME/.local/state/temperature"
LOG_FILE="$LOG_DIR/temperatures.csv"
mkdir -p "$LOG_DIR"

if [ ! -e "$LOG_FILE" ]; then
    printf 'timestamp,sensor,temp_c\n' > "$LOG_FILE"
fi

timestamp=$(date --iso-8601=seconds)
for temp_file in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$temp_file" ] || continue

    raw=$(<"$temp_file")
    [[ "$raw" =~ ^[0-9]+$ ]] || continue

    sensor_dir=${temp_file%/temp}
    sensor=$(<"$sensor_dir/type")
    printf '%s,%s,%s\n' "$timestamp" "$sensor" "$((raw / 1000))" >> "$LOG_FILE"
done
