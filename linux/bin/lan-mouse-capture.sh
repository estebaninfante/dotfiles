#!/usr/bin/env bash
set -uo pipefail

SOCKET="/run/user/$(id -u)/lan-mouse-socket.sock"

usage() {
    printf 'usage: %s on|off|status|toggle\n' "$(basename "$0")" >&2
    exit 2
}

# Liveness por PID, con ruta ABSOLUTA: ~/bin/pgrep es busybox y su `-x` compara
# contra la línea de comando completa, así que "lan-mouse --capture-backend …
# daemon" daba falso negativo y `off` se negaba a soltar la captura (el teclado
# seguía yendo a la otra máquina). No se usa `lan-mouse cli list` acá: llamarlo
# de más lo hace abortar con core dump cuando hay llamadas concurrentes.
daemon_up() {
    [ -S "$SOCKET" ] || return 1
    /usr/bin/pgrep -x lan-mouse >/dev/null 2>&1
}

# Una sola consulta al daemon por ejecución: cada `cli list` extra es una
# llamada concurrente más (y el binario no es reentrante).
CLIENT_LIST=""
CLIENT_LIST_DONE=""
client_lines() {
    if [ -z "$CLIENT_LIST_DONE" ]; then
        CLIENT_LIST="$(lan-mouse cli list 2>/dev/null)"
        CLIENT_LIST_DONE=1
    fi
    printf '%s\n' "$CLIENT_LIST"
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

    # Con Sunshine streameando, armar la captura es siempre un error: el
    # puntero que inyecta Moonlight entra en la zona del borde, lan-mouse se lo
    # queda y el ratón "desaparece" del stream. Sunshine deja sink-sunshine-*
    # como sink por defecto sólo mientras dura la sesión.
    if [ "$want" = on ] && pactl get-default-sink 2>/dev/null | grep -q '^sink-sunshine'; then
        printf 'sunshine streaming; capture stays released\n'
        exit 0
    fi

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
