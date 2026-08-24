#!/usr/bin/env bash
# Monitor de volante Logitech (G923/G29): vigila el botón PS (BTN_MODE,
# code 316) y emite "1" por pulsación. Lo consume quickshell (Process +
# SplitParser, patrón super-hold-monitor.sh) para abrir/cerrar el modo juegos.
set -euo pipefail

DEV=$(ls /dev/input/by-id/usb-Logitech_G923_*event-joystick 2>/dev/null | head -n1)
[[ -n "$DEV" ]] || DEV=$(ls /dev/input/by-id/usb-Logitech_G29_*event-joystick 2>/dev/null | head -n1)
[[ -n "$DEV" ]] || exit 1

evtest "$DEV" 2>/dev/null | awk '
    /type 1 \(EV_KEY\)/ && /(BTN_MODE|code 316)/ && /value 1$/ { print "1"; fflush() }
'