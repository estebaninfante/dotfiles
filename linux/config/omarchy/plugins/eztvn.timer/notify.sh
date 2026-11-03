#!/bin/bash
# One-shot alert fired by systemd-run when a timer or an eye break ends.
# Usage: notify.sh <timer|eye> <minutes>
set -u

kind=${1:-timer}
minutes=${2:-20}

case $kind in
eye)
  glyph="󰈈"
  headline="Descanso visual terminado"
  body="$minutes minutos mirando lejos. Vuelve a la pantalla."
  sound="complete"
  ;;
*)
  glyph="󰔛"
  headline="Temporizador"
  body="$minutes minutos completados."
  sound="alarm-clock-elapsed"
  ;;
esac

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
