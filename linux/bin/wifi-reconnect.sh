#!/usr/bin/env bash
# Fast WiFi reconnect — toggle off/on to force NetworkManager to reassociate.
# Useful after suspend when NM takes 15s+ to reconnect automatically.

set -euo pipefail

IFACE="${1:-wlo1}"

# Check if WiFi is enabled
if nmcli radio wifi | grep -q "desactivado\|disabled\|off"; then
    nmcli radio wifi on
    notify-send -t 3000 "WiFi" "Encendido — reconectando..."
    exit 0
fi

# Toggle off then on to force fast reconnection
nmcli radio wifi off
sleep 0.5
nmcli radio wifi on
notify-send -t 3000 "WiFi" "Reconectando..."
