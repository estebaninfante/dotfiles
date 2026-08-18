#!/usr/bin/env bash
# Pomodoro timer for Waybar
# States: idle -> work (25m) -> break (5m) -> idle
# Click toggles state via state file

WORK=3000    # 50 min
BREAK=600    # 10 min

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/pomodoro-waybar-state"

notify() {
    notify-send -a pomodoro "Pomodoro" "$1" -t 5000
}

emit() {
    local state end_time now remaining
    state=$(cat "$STATE_FILE" 2>/dev/null || echo "idle")
    end_time=$(cat "${STATE_FILE}.end" 2>/dev/null || echo 0)
    now=$(date +%s)

    case "$state" in
        idle)
            echo '{"text":"[ ]","class":"pomodoro-idle"}'
            ;;
        work)
            remaining=$(( end_time - now ))
            if [ "$remaining" -le 0 ]; then
                echo "break" > "$STATE_FILE"
                echo $(( now + BREAK )) > "${STATE_FILE}.end"
                notify "Work done! Break started (5m)"
                remaining=$BREAK
            fi
            printf '{"text":"%d:%02d","class":"pomodoro-work"}\n' $((remaining/60)) $((remaining%60))
            ;;
        break)
            remaining=$(( end_time - now ))
            if [ "$remaining" -le 0 ]; then
                echo "idle" > "$STATE_FILE"
                echo 0 > "${STATE_FILE}.end"
                notify "Break finished!"
                echo '{"text":"[ ]","class":"pomodoro-idle"}'
                return
            fi
            printf '{"text":"%d:%02d","class":"pomodoro-break"}\n' $((remaining/60)) $((remaining%60))
            ;;
    esac
}

toggle() {
    local state
    state=$(cat "$STATE_FILE" 2>/dev/null || echo "idle")
    case "$state" in
        idle)
            echo "work" > "$STATE_FILE"
            echo $(( $(date +%s) + WORK )) > "${STATE_FILE}.end"
            notify "Work started (25m)"
            ;;
        work)
            echo "idle" > "$STATE_FILE"
            echo 0 > "${STATE_FILE}.end"
            notify "Work cancelled"
            ;;
        break)
            echo "idle" > "$STATE_FILE"
            echo 0 > "${STATE_FILE}.end"
            notify "Break cancelled"
            ;;
    esac
}

# Handle click: toggle state
if [ "${1:-}" = "toggle" ]; then
    toggle
    exit 0
fi

# Init state file
echo "idle" > "$STATE_FILE"
echo 0 > "${STATE_FILE}.end"

# Main loop
while true; do
    emit
    sleep 1
done
