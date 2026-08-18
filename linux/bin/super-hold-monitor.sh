#!/usr/bin/env bash
# Monitor del estado de la tecla Super (keyd: capslock = leftmeta) para quickshell.
# Emite "1" al presionar KEY_LEFTMETA y "0" al soltar, una linea por evento.
# Consumido por shell.qml (Process stdout -> SplitParser).
set -u

dev=""
for d in /sys/class/input/event*; do
    name=$(cat "$d/device/name" 2>/dev/null) || continue
    if [[ "$name" == "keyd virtual keyboard" ]]; then
        dev="/dev/input/$(basename "$d")"
        break
    fi
done

if [[ -z "$dev" ]]; then
    echo "super-hold-monitor: no se encontro 'keyd virtual keyboard'" >&2
    exit 1
fi

stdbuf -oL evtest "$dev" 2>/dev/null | awk '
    /KEY_LEFTMETA/ {
        if ($0 ~ /value 1/) { print "1"; fflush() }
        else if ($0 ~ /value 0/) { print "0"; fflush() }
    }
'
