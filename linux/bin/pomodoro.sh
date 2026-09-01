#!/usr/bin/env bash
# pomodoro.sh — pomodoro + recordatorio de ojos para el centro de quickshell
# (pestaña Pomodoro del DateMenu + pill flotante). Sustituyó a pomodoro-waybar.sh.
# Estado en $XDG_RUNTIME_DIR/pomodoro/ (sobrevive a reinicios de quickshell).
# Config en ~/.local/state/quickshell/pomodoro.conf (clave=valor).
# Uso: pomodoro.sh {start|pause|resume|stop|skip|status|config [clave valor]}

set -euo pipefail

RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/pomodoro"
CONF_DIR="$HOME/.local/state/quickshell"
CONF="$CONF_DIR/pomodoro.conf"
mkdir -p "$RUN_DIR" "$CONF_DIR"
[ -f "$CONF" ] || printf 'work_min=25\nbreak_min=5\neyes_min=20\neyes_on=1\n' > "$CONF"

cfg() { grep -E "^$1=" "$CONF" 2>/dev/null | head -1 | cut -d= -f2 || echo "$2"; }
state_get() { cat "$RUN_DIR/state" 2>/dev/null || echo idle; }
end_get() { cat "$RUN_DIR/end" 2>/dev/null || echo 0; }
eyes_get() { cat "$RUN_DIR/eyes_end" 2>/dev/null || echo 0; }
cycle_get() { cat "$RUN_DIR/cycle" 2>/dev/null || echo 0; }

notify() { notify-send -a Pomodoro -t 5000 "Pomodoro" "$1" 2>/dev/null || true; }

set_conf() {
    local k="$1" v="$2"
    case "$k" in
        work_min|break_min|eyes_min) [[ "$v" =~ ^[0-9]+$ ]] || { echo "valor inválido"; exit 1; } ;;
        eyes_on) [[ "$v" == "0" || "$v" == "1" ]] || { echo "valor inválido"; exit 1; } ;;
        *) echo "clave inválida"; exit 1 ;;
    esac
    if grep -qE "^$k=" "$CONF"; then sed -i "s/^$k=.*/$k=$v/" "$CONF"; else printf '%s=%s\n' "$k" "$v" >> "$CONF"; fi
}

start() {
    printf 'work' > "$RUN_DIR/state"
    printf '%s' $(( $(date +%s) + $(cfg work_min 25) * 60 )) > "$RUN_DIR/end"
    printf '0' > "$RUN_DIR/cycle"
    if [ "$(cfg eyes_on 1)" = "1" ]; then
        printf '%s' $(( $(date +%s) + $(cfg eyes_min 20) * 60 )) > "$RUN_DIR/eyes_end"
    else
        printf '0' > "$RUN_DIR/eyes_end"
    fi
    rm -f "$RUN_DIR/remain" "$RUN_DIR/eyes_remain"
    notify "Pomodoro iniciado — $(cfg work_min 25) min de trabajo"
}

pause() {
    local s; s="$(state_get)"
    case "$s" in
        work|break)
            printf '%s' $(( $(end_get) - $(date +%s) )) > "$RUN_DIR/remain"
            printf '%s' $(( $(eyes_get) - $(date +%s) )) > "$RUN_DIR/eyes_remain"
            printf 'paused_%s' "$s" > "$RUN_DIR/state"
            ;;
    esac
}

resume() {
    local s; s="$(state_get)"
    case "$s" in
        paused_work) printf 'work' > "$RUN_DIR/state" ;;
        paused_break) printf 'break' > "$RUN_DIR/state" ;;
        *) return 0 ;;
    esac
    printf '%s' $(( $(date +%s) + $(cat "$RUN_DIR/remain" 2>/dev/null || echo 0) )) > "$RUN_DIR/end"
    if [ "$(cfg eyes_on 1)" = "1" ]; then
        printf '%s' $(( $(date +%s) + $(cat "$RUN_DIR/eyes_remain" 2>/dev/null || echo 0) )) > "$RUN_DIR/eyes_end"
    fi
    rm -f "$RUN_DIR/remain" "$RUN_DIR/eyes_remain"
}

stop() {
    printf 'idle' > "$RUN_DIR/state"
    printf '0' > "$RUN_DIR/end"
    printf '0' > "$RUN_DIR/eyes_end"
    printf '0' > "$RUN_DIR/cycle"
    rm -f "$RUN_DIR/remain" "$RUN_DIR/eyes_remain"
}

skip() {
    local s; s="$(state_get)"
    case "$s" in
        work|paused_work)
            printf 'break' > "$RUN_DIR/state"
            printf '%s' $(( $(date +%s) + $(cfg break_min 5) * 60 )) > "$RUN_DIR/end"
            rm -f "$RUN_DIR/remain"
            notify "Saltado — descansa $(cfg break_min 5) min"
            ;;
        break|paused_break)
            notify "Pomodoro terminado — $(cycle_get) ciclo(s)"
            stop
            ;;
    esac
}

status() {
    local now; now="$(date +%s)"
    local s; s="$(state_get)"
    local end; end="$(end_get)"
    local eyes; eyes="$(eyes_get)"
    local remain=0 eyes_in=-1

    case "$s" in
        work|break)
            remain=$(( end - now ))
            if [ "$remain" -le 0 ]; then
                if [ "$s" = "work" ]; then
                    local c; c=$(( $(cycle_get) + 1 ))
                    printf '%s' "$c" > "$RUN_DIR/cycle"
                    printf 'break' > "$RUN_DIR/state"
                    printf '%s' $(( now + $(cfg break_min 5) * 60 )) > "$RUN_DIR/end"
                    s="break"; remain=$(( $(cfg break_min 5) * 60 ))
                    notify "Ciclo $c listo — descansa $(cfg break_min 5) min"
                else
                    local c; c="$(cycle_get)"
                    stop
                    s="idle"; remain=0
                    notify "Descanso terminado — $c ciclo(s) completados"
                fi
            fi
            ;;
        paused_work|paused_break)
            remain=$(cat "$RUN_DIR/remain" 2>/dev/null || echo 0)
            ;;
    esac

    if [ "$s" != "idle" ] && [ "$(cfg eyes_on 1)" = "1" ] && [ "$eyes" -gt 0 ]; then
        if [ "$s" = "paused_work" ] || [ "$s" = "paused_break" ]; then
            eyes_in=$(cat "$RUN_DIR/eyes_remain" 2>/dev/null || echo -1)
        else
            eyes_in=$(( eyes - now ))
            if [ "$eyes_in" -le 0 ]; then
                notify "Mira lejos — descansa la vista unos segundos"
                eyes_in=$(( $(cfg eyes_min 20) * 60 ))
                printf '%s' $(( now + eyes_in )) > "$RUN_DIR/eyes_end"
            fi
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$s" "$remain" "$(cfg work_min 25)" "$(cfg break_min 5)" "$(cfg eyes_min 20)" "$(cfg eyes_on 1)" "$eyes_in" "$(cycle_get)"
}

case "${1:-}" in
    start) start ;;
    pause) pause ;;
    resume) resume ;;
    stop) stop ;;
    skip) skip ;;
    status) status ;;
    config)
        if [ $# -ge 3 ]; then set_conf "$2" "$3"; else cat "$CONF"; fi ;;
    *) echo "uso: pomodoro.sh {start|pause|resume|stop|skip|status|config [clave valor]}"; exit 1 ;;
esac
