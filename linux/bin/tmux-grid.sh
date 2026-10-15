#!/usr/bin/env bash
# tmux-grid.sh — matriz exacta de panes (cols x rows) para vigilar varios
# agentes (opencode/claude) a la vez, todos visibles sin switchear.
# Genera el layout string de tmux y lo aplica con select-layout (atomico).
#
# Uso: tmux-grid.sh [colsxrows|auto] [window-target]
#   colsxrows  ej. 4x2 (4 columnas, 2 filas = 8 agentes), 3x3, 2x4...
#   auto       minimo MIN_W de ancho y MIN_H de alto por panel (ver abajo),
#              maximizando las lineas visibles de cada agente (default)
#   window     target tmux de la ventana (default: TMUX_PANE)
#
# El pane 0 queda arriba-izquierda; el resto fila por fila (row-major).

set -euo pipefail

MODE="${1:-auto}"
TARGET="${2:-${TMUX_PANE:-}}"

if [[ -z "$TARGET" ]]; then
    exit 0
fi

MIN_W="${TMUX_MIN_W:-72}"
MIN_H="${TMUX_MIN_H:-12}"

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
    # ── Auto: maximizar alto de panel respetando MIN_W x MIN_H ──
    # Se prueban cantidades de columnas c=1..n. Cada panel debe medir al
    # menos MIN_W de ancho (para leer bloques de codigo sin cortar) y
    # MIN_H de alto. Entre los validos se elige el de mayor alto (mas
    # lineas visibles por agente). Si ninguno cumple, se degrada al que
    # maximiza el peor margen relativo (misma logica, sin minimos).
    # Overridables: TMUX_MIN_W / TMUX_MIN_H en el entorno.
    best_c=0; best_h=-1; best_w=-1
    fb_c=0; fb_score=-1
    for ((c = 1; c <= n; c++)); do
        r=$(( (n + c - 1) / c ))
        cellw=$(( (W - (c - 1)) / c ))
        cellh=$(( (H - (r - 1)) / r ))
        (( cellw < 1 )) && cellw=1
        (( cellh < 1 )) && cellh=1
        sw=$(( cellw * 1000 / MIN_W ))
        sh=$(( cellh * 1000 / MIN_H ))
        s=$(( sw < sh ? sw : sh ))
        if (( s > fb_score )); then fb_score=$s; fb_c=$c; fi
        if (( cellw >= MIN_W && cellh >= MIN_H )); then
            if (( cellh > best_h || (cellh == best_h && cellw > best_w) )); then
                best_h=$cellh; best_w=$cellw; best_c=$c
            fi
        fi
    done
    if (( best_c > 0 )); then
        cols=$best_c
    else
        cols=$fb_c
        (( cols < 1 )) && cols=1
    fi
fi

rows=$(( (n + cols - 1) / cols ))

# ── Construir layout string ──
# Formato: <checksum>,WxH,0,0<arbol>
#   checksum = CRC-16 rotatorio del RESTO del string (ver layout-custom.c
#   de tmux); sin checksum correcto tmux rechaza el layout ("invalid layout").
#   Arbol: {} = split horizontal (hijos izq|der), [] = stack vertical;
#   leaf = WxH,X,Y,paneId (id sin '%'); fila única usa {} directo.
tmux_checksum() {
    local s="$1" csum=0 byte i
    for ((i = 0; i < ${#s}; i++)); do
        printf -v byte '%d' "'${s:$i:1}"
        csum=$(( ((csum >> 1) | ((csum & 1) << 15)) + byte & 0xFFFF ))
    done
    printf '%04x' "$csum"
}

# ids de pane sin '%'
for ((i = 0; i < n; i++)); do
    panes[$i]="${panes[$i]#%}"
done

body="${W}x${H},0,0"

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
    body+="[$(IFS=,; echo "${filas[*]}")]"
else
    body+="{${row}}"
fi

layout="$(tmux_checksum "$body"),$body"

# Aplicar; si el string no es valido, tiled como red de seguridad
if ! tmux select-layout -t "$TARGET" "$layout" 2>/dev/null; then
    tmux select-layout -t "$TARGET" tiled
fi

tmux set -w -t "$TARGET" @layout_mode grid
tmux set -w -t "$TARGET" @layout_panes "$n"
