#!/usr/bin/env bash
# Modo juegos — backend. quickshell maneja trigger/confirm/transición;
# este script solo ejecuta: cerrar apps (excepto keep-list), Steam en
# segundo plano y Cartridges en ws 10 (window rule hyprland lo hace
# fullscreen).
#
# Los dispatchers lua de Hyprland 0.56 (dsp.window.kill/close + focus)
# devuelven 'ok' pero no matan ventanas reales → cierre por SIGTERM al
# pid que expone `hyprctl clients -j` (kitty/discord/brave/spotify lo
# manejan graceful).
#
# USO:
#   game-mode.sh            → entrar (cierra apps + Steam bg + Cartridges)
#   game-mode.sh noclose    → entrar sin cerrar apps
#   game-mode.sh exit       → salir (cierra Cartridges y vuelve a ws 5)
set -euo pipefail

FLAG=/tmp/gamemode.flag

# Apps que NO se cierran (UI del sistema + las que el usuario sigue viendo).
KEEP='quickshell|swaync|swayosd-server|discord|whatsapp|whatsie|spotify|sunshine|lan.?mouse'

# workspace focus (lua): hl.dispatch obligatorio, sin wrapper no mueve.
ws_focus() {
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"$1\" }))" >/dev/null 2>&1 || true
}

# PIDs de ventanas cuya clase NO matchea KEEP (dedup).
nonkeep_pids() {
    hyprctl clients -j 2>/dev/null \
        | jq -r --arg k "$KEEP" '.[] | select(.class | test($k; "i") | not) | .pid' \
        | sort -un
}

# PIDs de ventanas de Cartridges.
cartridges_pids() {
    hyprctl clients -j 2>/dev/null \
        | jq -r '.[] | select(.class | test("cartridges"; "i")) | .pid' \
        | sort -un
}

exit_game() {
    rm -f "$FLAG"
    mapfile -t cps < <(cartridges_pids)
    if (( ${#cps[@]} )); then
        kill -TERM "${cps[@]}" 2>/dev/null || true
    fi
    pkill -f '.cartridges-wrapped' 2>/dev/null || true
    ws_focus 5
    exit 0
}

case "${1:-}" in
    exit) exit_game ;;
esac

touch "$FLAG"

if [[ "${1:-}" != "noclose" ]]; then
    mapfile -t ps < <(nonkeep_pids)
    if (( ${#ps[@]} )); then
        kill -TERM "${ps[@]}" 2>/dev/null || true
        sleep 2
    fi
fi

# Steam en segundo plano (si no corre ya).
pgrep -x steam >/dev/null 2>&1 || { steam -silent &>/dev/null & disown; }

# Cartridges limpio: matar instancias huérfanas y lanzar una sola vez.
pkill -f '.cartridges-wrapped' 2>/dev/null || true
{ cartridges &>/dev/null & disown; }

# Mover al ws de juegos; esperar a que cartridges levante ventana (máx 15s)
# para que el overlay de carga se cierre cuando esté listo, no antes.
ws_focus 10
for _ in $(seq 1 30); do
    if hyprctl clients -j 2>/dev/null \
        | jq -e '.[] | select(.class | test("cartridges"; "i"))' >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done