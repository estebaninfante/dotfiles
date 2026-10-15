#!/usr/bin/env bash
# tmux-newpane.sh — Agrega un panel y reaplica la grilla automatica.
#
# Si el window estaba en modo lectura (1 panel, kitty angosto), primero
# devuelve el ancho completo y espera a que tmux reciba el resize; recien
# entonces divide y calcula la grilla, para que el layout se elija con el
# ancho real (si no, elegiria columnas para el ancho angosto).
#
# Uso: tmux-newpane.sh <window-target> [cwd]

set -uo pipefail

WIN="${1:-${TMUX_PANE:-}}"
CWD="${2:-$HOME}"
[[ -n "$WIN" ]] || exit 0

# Hold: mientras dura esto, el hook client-resized (tmux-readwidth.sh) no debe
# reaplicar la columna de lectura y romper el ancho completo que necesitamos.
tmux set -w -t "$WIN" @readwidth_hold 1
trap 'tmux set -w -t "$WIN" @readwidth_hold 0 2>/dev/null || true' EXIT

# 1) ancho completo en el cliente que muestra esta ventana
tmux-readwidth.sh --normal "$WIN" >/dev/null 2>&1 || true

# 2) esperar a que tmux reciba el resize (estabiliza dos lecturas seguidas)
prev=-1
stable=0
for ((i = 0; i < 25; i++)); do
    w=$(tmux display-message -p -t "$WIN" '#{window_width}' 2>/dev/null) || break
    if [[ "$w" == "$prev" ]]; then
        stable=$((stable + 1))
    else
        stable=0
    fi
    prev="$w"
    (( stable >= 2 && i >= 4 )) && break
    sleep 0.03
done

# 3) dividir y reaplicar la grilla con el ancho ya correcto
tmux split-window -h -t "$WIN" -c "$CWD" 2>/dev/null || true
tmux-grid.sh auto "$WIN"

# 4) liberar el hold y re-evaluar el padding segun la cantidad final de paneles
tmux set -w -t "$WIN" @readwidth_hold 0 2>/dev/null || true
tmux-readwidth.sh "$WIN" >/dev/null 2>&1 || true
