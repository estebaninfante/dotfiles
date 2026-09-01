#!/usr/bin/env bash
# tmux-fibonacci.sh — reparte los panes de la ventana actual en proporciones
# de Fibonacci (13:8:5:3:2:1...) para ver el maximo de panes/agentes a la vez
# conservando contenido visible en todos.
#
# Uso: tmux-fibonacci.sh [min] [window-target]
#   min     = ancho/alto minimo por pane (default 12)
#   window  = target tmux de la ventana (default: pane activo via TMUX_PANE)
#
# Orientacion automatica: columnas si la ventana es mas ancha que alta,
# filas si es mas alta que ancha.

set -euo pipefail

MIN="${1:-12}"
TARGET="${2:-${TMUX_PANE:-}}"

if [[ -z "$TARGET" ]]; then
    exit 0
fi

# Panes de la ventana target (orden por indice)
mapfile -t panes < <(tmux list-panes -t "$TARGET" -F '#{pane_id}' 2>/dev/null || true)
n=${#panes[@]}
if (( n < 2 )); then
    exit 0
fi
first="${panes[0]}"

# Dimensiones de la ventana
read -r W H <<< "$(tmux display-message -p -t "$first" '#{window_width} #{window_height}')"

# Pesos Fibonacci, mayor primero: 13 8 5 3 2 1 1 1...
fib=(13 8 5 3 2 1)
weights=()
for ((i = 0; i < n; i++)); do
    if (( i < ${#fib[@]} )); then
        weights+=("${fib[$i]}")
    else
        weights+=("1")
    fi
done
total=$(IFS=+; echo "$(( ${weights[*]} ))")

# Orientacion: columnas (x) si mas ancha que alta, filas (y) si no.
# Se descuentan los bordes entre panes (1 col/fila cada uno).
axis="x"
main="$W"
if (( H > W )); then
    axis="y"
    main="$H"
fi
main=$(( main - (n - 1) ))

# Reparto: proporcional a Fibonacci; cada pane respeta el minimo;
# el ultimo absorbe el resto (redondeos).
sizes=()
remaining="$main"
for ((i = 0; i < n; i++)); do
    if (( i == n - 1 )); then
        sizes+=("$remaining")
        break
    fi
    ideal=$(( main * weights[i] / total ))
    # garantizar espacio minimo para los panes restantes
    need=$(( MIN * (n - 1 - i) ))
    if (( remaining - ideal < need )); then
        ideal=$(( remaining - need ))
    fi
    if (( ideal < MIN )); then
        ideal="$MIN"
    fi
    sizes+=("$ideal")
    remaining=$(( remaining - ideal ))
done

# Aplicar: resize absoluto (-x/-y) en orden; los ids de pane son unicos
# por servidor, no dependen del target de ventana.
for ((i = 0; i < n; i++)); do
    tmux resize-pane -t "${panes[$i]}" "-$axis" "${sizes[$i]}" 2>/dev/null || true
done
