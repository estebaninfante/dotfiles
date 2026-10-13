#!/usr/bin/env bash
set -uo pipefail

SOCKET="/run/user/$(id -u)/lan-mouse-socket.sock"

usage() {
    printf 'usage: %s on|off|status|toggle\n' "$(basename "$0")" >&2
    exit 2
}

daemon_up() {
    [ -S "$SOCKET" ] && pgrep -x lan-mouse >/dev/null 2>&1
}

client_lines() {
    lan-mouse cli list 2>/dev/null
}

release_held_ids() {
    client_lines | sed -n 's/^id \([0-9][0-9]*\):.*active: false.*/\1/p'
}

active_held_ids() {
    client_lines | sed -n 's/^id \([0-9][0-9]*\):.*active: true.*/\1/p'
}

capture_state() {
    if [ -n "$(active_held_ids)" ]; then
        echo active
    else
        echo released
    fi
}

set_capture() {
    local want="$1" verb pending
    case "$want" in
        on)  verb=activate;   pending="$(release_held_ids)" ;;
        off) verb=deactivate; pending="$(active_held_ids)" ;;
        *)   usage ;;
    esac

    if ! daemon_up; then
        printf 'lan-mouse daemon not running; capture stays %s\n' "$(capture_state)"
        exit 0
    fi

    local id
    for id in $pending; do
        lan-mouse cli "$verb" "$id" >/dev/null 2>&1 || true
    done
    printf 'capture %s\n' "$(capture_state)"
}

target="${1:-}"
[ -n "$target" ] || usage

case "$target" in
    on|off)
        set_capture "$target"
        ;;
    status)
        if daemon_up; then
            printf 'daemon: running\n'
        else
            printf 'daemon: stopped\n'
        fi
        printf 'capture: %s\n' "$(capture_state)"
        client_lines || true
        ;;
    toggle)
        if [ "$(capture_state)" = active ]; then
            set_capture off
        else
            set_capture on
        fi
        ;;
    *)
        usage
        ;;
esac
