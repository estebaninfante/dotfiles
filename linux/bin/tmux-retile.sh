#!/usr/bin/env bash

set -euo pipefail

while IFS='|' read -r win mode panes stored ww wh pw ph; do
    [[ "$mode" == "grid" || "$mode" == "fib" ]] || continue
    [[ "$panes" =~ ^[0-9]+$ ]] || continue
    # Curacion: si quedo un solo panel que NO llena la ventana (celdas fantasma
    # que tmux deja al matar paneles de un layout hecho a mano), se normaliza
    # con el layout nativo tiled. Sin esto la ventana queda a medias y seguir
    # operando encima puede colgar el servidor.
    if (( panes == 1 )) && [[ "$ww" =~ ^[0-9]+$ && "$wh" =~ ^[0-9]+$ && "$pw" =~ ^[0-9]+$ && "$ph" =~ ^[0-9]+$ ]] \
        && (( pw != ww || ph != wh )); then
        tmux select-layout -t "$win" tiled 2>/dev/null || true
    fi
    if [[ "$stored" =~ ^[0-9]+$ ]] && (( panes < stored && panes >= 2 )); then
        if [[ "$mode" == "grid" ]]; then
            tmux-grid.sh auto "$win"
        else
            tmux-fibonacci.sh 12 "$win"
        fi
        continue
    fi
    if [[ "$panes" != "$stored" ]]; then
        tmux set -w -t "$win" @layout_panes "$panes" 2>/dev/null || true
    fi
done < <(tmux list-windows -a -F '#{window_id}|#{@layout_mode}|#{window_panes}|#{@layout_panes}|#{window_width}|#{window_height}|#{pane_width}|#{pane_height}')
