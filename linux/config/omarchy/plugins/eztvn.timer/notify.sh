#!/bin/bash
# One-shot alert fired by systemd-run when the countdown ends.
# Usage: notify.sh <minutes>
set -u

minutes=${1:-20}

glyph="󰔛"
headline="Temporizador"
body="$minutes minutos completados."
sound="alarm-clock-elapsed"

if command -v pw-play >/dev/null 2>&1 && [[ -f /usr/share/sounds/freedesktop/stereo/$sound.oga ]]; then
  pw-play --volume 0.7 "/usr/share/sounds/freedesktop/stereo/$sound.oga" >/dev/null 2>&1 &
fi

if command -v omarchy-notification-send >/dev/null 2>&1; then
  exec omarchy-notification-send -g "$glyph" -u normal "$headline" "$body"
fi

if command -v notify-send >/dev/null 2>&1; then
  exec notify-send "$headline" "$body"
fi

exit 0
