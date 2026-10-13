#!/usr/bin/env bash

set -euo pipefail

while IFS='|' read -r win mode panes stored; do
    [[ "$mode" == "grid" || "$mode" == "fib" ]] || continue
    [[ "$panes" =~ ^[0-9]+$ ]] || continue
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
done < <(tmux list-windows -a -F '#{window_id}|#{@layout_mode}|#{window_panes}|#{@layout_panes}')
