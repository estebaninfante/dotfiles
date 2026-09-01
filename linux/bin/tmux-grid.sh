#!/usr/bin/env bash
# tmux-grid.sh — matriz exacta de panes (cols x rows) para vigilar varios
# agentes (opencode/claude) a la vez, todos visibles sin switchear.
# Genera el layout string de tmux y lo aplica con select-layout (atomico).
#
# Uso: tmux-grid.sh [colsxrows|auto] [window-target]
#   colsxrows  ej. 4x2 (4 columnas, 2 filas = 8 agentes), 3x3, 2x4...
#   auto       elige la grilla que mejor aprovecha el aspect ratio de la
#              ventana (default si se omite el argumento)
#   window     target tmux de la ventana (default: TMUX_PANE)
#
# El pane 0 queda arriba-izquierda; el resto fila por fila (row-major).

set -euo pipefail

MODE="${1:-auto}"
TARGET="${2:-${TMUX_PANE:-}}"

if [[ -z "$TARGET" ]]; then
    exit 0
fi

MIN_W=20
MIN_H=6

# Dimensiones + panes de la ventana target (ids ordenados por indice;
# el layout string de tmux referencia panes por id, sin el '%')
read -r W H <<< "$(tmux display-message -p -t "$TARGET" '#{window_width} #{window_height}')"
mapfile -t panes < <(tmux list-panes -t "$TARGET" -F '#{pane_index} #{pane_id}' 2>/dev/null | sort -n | cut -d' ' -f2 || true)
n=${#panes[@]}
if (( n < 2 )); then
    exit 0
fi

cols=0
if [[ "$MODE" != "auto" && "$MODE" != "" ]]; then
    cols="${MODE%%x*}"
fi
if (( cols < 1 )); then
    # ── Auto: probar filas r=1..n, cols=ceil(n/r), elegir mejor aspect ──
    # Celda objetivo ~16:9 (1.7); penalizar celdas muy chicas.
    best_cost=0
    best_r=0
    for ((r = 1; r <= n; r++)); do
        c=$(( (n + r - 1) / r ))
        cellw=$(( (W - (c - 1)) / c ))
        cellh=$(( (H - (r - 1)) / r ))
        if (( cellw < MIN_W || cellh < MIN_H )); then
            continue
        fi
        ratio=$(( cellw * 1000 / cellh ))
        dist=$(( ratio - 1700 ))
        (( dist < 0 )) && dist=$(( -dist ))
        cost=$(( dist * dist / 1000 ))
        if (( best_r == 0 || cost < best_cost )); then
            best_cost=$cost
            best_r=$r
        fi
    done
    if (( best_r == 0 )); then
        best_r=$(( n > 4 ? 4 : n ))   # fallback: filas de a uno por ancho
    fi
    cols=$(( (n + best_r - 1) / best_r ))
fi

rows=$(( (n + cols - 1) / cols ))

# ── Construir layout string ──
# Formato: <base>,WxH,0,0{leaf,leaf,...}  (1 fila)
#       o  <base>,WxH,0,0[fila,fila]  (varias filas; [] = stack vertical,
#                                      {} = split horizontal; leaf =
#                                      WxH,X,Y,paneId — id sin '%')
wl="$(tmux display-message -p -t "$TARGET" '#{window_layout}')"
base="${wl%%,*}"

# ids de pane sin '%'
for ((i = 0; i < n; i++)); do
    panes[$i]="${panes[$i]#%}"
done

layout="$base,${W}x${H},0,0"

idx=0
y=0
filas=()
for ((r = 0; r < rows; r++)); do
    # alto de la fila: H menos separadores, repartido (resto a las primeras)
    th=$(( H - (rows - 1) ))
    h=$(( th / rows + (r < th % rows ? 1 : 0) ))

    # panes en esta fila (la ultima puede quedar corta -> mas anchos)
    k=$cols
    if (( r == rows - 1 )); then
        k=$(( n - cols * (rows - 1) ))
    fi

    row=""
    x=0
    for ((c = 0; c < k; c++)); do
        tw=$(( W - (k - 1) ))
        w=$(( tw / k + (c < tw % k ? 1 : 0) ))
        row+="${row:+,}${w}x${h},${x},${y},${panes[$idx]}"
        x=$(( x + w + 1 ))
        idx=$(( idx + 1 ))
    done

    filas+=("${W}x${h},0,${y}{${row}}")
    y=$(( y + h + 1 ))
done

if (( rows > 1 )); then
    layout+="[$(IFS=,; echo "${filas[*]}")]"
else
    layout+="{${row}}"
fi

# Aplicar; si el string no es valido, tiled como red de seguridad
if ! tmux select-layout -t "$TARGET" "$layout" 2>/dev/null; then
    tmux select-layout -t "$TARGET" tiled
fi
