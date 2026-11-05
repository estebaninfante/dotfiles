#!/usr/bin/env bash
set -uo pipefail

SOCKET="/run/user/$(id -u)/lan-mouse-socket.sock"

usage() {
    printf 'usage: %s on|off|status|toggle\n' "$(basename "$0")" >&2
    exit 2
}

# Liveness por RPC sobre el socket, NO por nombre de proceso: ~/bin/pgrep es el
# de busybox y `pgrep -x lan-mouse` da falso negativo (el comando existe y
# falla), asi `off` se negaba a soltar la captura y el teclado seguia yendo a
# la otra maquina. Que `cli list` conteste ya prueba que el daemon esta vivo;
# el socket huerfano (daemon muerto) no contesta y `timeout` lo corta.
daemon_up() {
    [ -S "$SOCKET" ] || return 1
    timeout 2 lan-mouse cli list >/dev/null 2>&1
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
