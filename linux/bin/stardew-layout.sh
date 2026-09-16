#!/bin/bash
# stardew-layout.sh - Auto-switch to QWERTY when Stardew Valley opens
# Run as systemd user service or from hyprland autostart

socat -u UNIX-CONNECT:/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - 2>/dev/null | \
while read -r line; do
    case "$line" in
        *activewindow*|*openwindow*)
            # Check if Stardew Valley is the active window
            active=$(hyprctl activewindow -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('class',''))" 2>/dev/null)
            case "$active" in
                *StardewValley*|*stardew*|*steam_app*)
                    switch-layout.sh 2  # US QWERTY
                    ;;
            esac
            ;;
    esac
done
