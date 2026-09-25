#!/usr/bin/env bash
# State and actions for the dashboard toggles page.
#
# One script so the QML never has to know which CLI owns which switch, and so
# every "is it on?" answer comes from the same place the action that changes it
# goes through. `state` prints one JSON object; every other verb toggles.
#
# Deliberately best-effort: a missing nmcli or pactl reports the switch as off
# rather than failing the whole probe.

set -u

state_dir="${HOME}/.local/state/omarchy"
settings_file="${state_dir}/notifications.json"

wifi_on() {
  command -v nmcli >/dev/null 2>&1 || return 1
  [[ $(nmcli -t -f WIFI general 2>/dev/null) == enabled ]]
}

bt_on() {
  command -v omarchy-bluetooth-power >/dev/null 2>&1 || return 1
  omarchy-bluetooth-power is-on >/dev/null 2>&1
}

mute_on() {
  command -v pactl >/dev/null 2>&1 || return 1
  [[ $(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null) == *yes* ]]
}

volume_percent() {
  command -v pactl >/dev/null 2>&1 || { echo 0; return; }
  pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null |
    awk 'NR == 1 { for (i = 1; i <= NF; i++) if ($i ~ /%$/){ sub("%", "", $i); print $i; exit } }'
}

nightlight_on() {
  command -v omarchy-toggle-nightlight >/dev/null 2>&1 || return 1
  [[ $(omarchy-toggle-nightlight --status 2>/dev/null | jq -r '.enabled // false' 2>/dev/null) == true ]]
}

dnd_on() {
  [[ -r $settings_file ]] || return 1
  [[ $(jq -r '.dnd // false' "$settings_file" 2>/dev/null) == true ]]
}

brightness_percent() {
  command -v omarchy-brightness-display >/dev/null 2>&1 || { echo -1; return; }
  local value
  value=$(omarchy-brightness-display 2>/dev/null)
  if [[ $value =~ ^[0-9]+$ ]]; then echo "$value"; else echo -1; fi
}

bool() { if "$@" >/dev/null 2>&1; then echo true; else echo false; fi; }

emit_state() {
  local wifi bt muted nightlight dnd airplane volume brightness
  wifi=$(bool wifi_on)
  bt=$(bool bt_on)
  muted=$(bool mute_on)
  nightlight=$(bool nightlight_on)
  dnd=$(bool dnd_on)
  volume=$(volume_percent)
  brightness=$(brightness_percent)
  [[ -z $volume ]] && volume=0

  # Airplane mode is "both radios down" — the same state the toggle sets.
  if [[ $wifi == false && $bt == false ]]; then airplane=true; else airplane=false; fi

  printf '{"wifi":%s,"bluetooth":%s,"muted":%s,"volume":%s,"nightlight":%s,"dnd":%s,"airplane":%s,"brightness":%s}\n' \
    "$wifi" "$bt" "$muted" "$volume" "$nightlight" "$dnd" "$airplane" "$brightness"
}

case "${1:-state}" in
  state)
    emit_state
    ;;
  wifi)
    nmcli radio wifi toggle
    ;;
  bluetooth)
    omarchy-bluetooth-power toggle
    ;;
  mute)
    pactl set-sink-mute @DEFAULT_SINK@ toggle
    ;;
  volume)
    case "${2:-}" in
      up) pactl set-sink-volume @DEFAULT_SINK@ +5% ;;
      down) pactl set-sink-volume @DEFAULT_SINK@ -5% ;;
    esac
    ;;
  nightlight)
    omarchy-toggle-nightlight
    ;;
  dnd)
    omarchy-shell notifications toggleDnd
    ;;
  airplane)
    if ! wifi_on && ! bt_on; then
      nmcli radio wifi on
      omarchy-bluetooth-power on
    else
      nmcli radio wifi off
      omarchy-bluetooth-power off
    fi
    ;;
  brightness)
    case "${2:-}" in
      up) omarchy-brightness-display --no-osd +5% ;;
      down) omarchy-brightness-display --no-osd 5%- ;;
    esac
    ;;
  *)
    echo "Usage: toggles.sh [state|wifi|bluetooth|mute|volume up|volume down|nightlight|dnd|airplane|brightness up|brightness down]" >&2
    exit 1
    ;;
esac
