#!/usr/bin/env bash
# tmux-readwidth.sh — Modo lectura dinamico adaptado al ancho de la ventana.
#
# Ajusta el padding horizontal de kitty segun:
#   - cuantos paneles tiene el window activo de cada cliente tmux:
#       1 panel    -> columna de lectura centrada (padding calculado para
#                     dejar ~TMUX_READ_COLS columnas de texto legible)
#       2+ paneles -> ancho completo (padding chico fijo; lo maneja tmux-grid.sh)
#   - el ancho de la ventana kitty: en ventanas angostas el padding baja
#     solo, hasta 0, para no dejar el texto ilegible. El padding nunca quita
#     mas de lo que hace falta para llegar a las columnas objetivo.
#
# Ejemplo: en una ventana de 80 columnas el padding es 0 (texto completo);
# en una de 160 se centra una columna de ~TMUX_READ_COLS columnas.
#
# Usa el control remoto de kitty (socket-only) y lee KITTY_LISTEN_ON /
# KITTY_WINDOW_ID / KITTY_PUBLIC_KEY del entorno del cliente tmux
# (/proc/<pid>/environ), asi apunta al kitty correcto aunque haya varias
# instancias/ventanas.
#
# Uso: tmux-readwidth.sh [--auto|--normal|--reading] [target-window]
#   --auto     (default) decide por cantidad de paneles del window activo
#   --normal   fuerza ancho completo en los clientes que muestran target
#   --reading  fuerza columna de lectura en los clientes que muestran target
#
# Overrides:
#   TMUX_READ_COLS  columnas objetivo de la columna de lectura   (default 100)
#   TMUX_READ_PAD   tope de padding en modo lectura              (default 190)
#   TMUX_NORMAL_PAD padding horizontal con 2+ paneles            (default 20)
#   TMUX_READ_RATIO columnas que quita cada unidad de padding. Si no se
#                   define, se calibra una vez y se cachea en el runtime dir.

set -uo pipefail

MODE="auto"
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --auto)    MODE="auto" ;;
        --normal)  MODE="normal" ;;
        --reading) MODE="reading" ;;
        *)         TARGET="$arg" ;;
    esac
done

READ_COLS="${TMUX_READ_COLS:-100}"
READ_PAD="${TMUX_READ_PAD:-190}"
NORMAL_PAD="${TMUX_NORMAL_PAD:-20}"

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}/tmux-readwidth"
mkdir -p "$RUNTIME" 2>/dev/null || true
RATIO_FILE="$RUNTIME/ratio"

# Serializa ejecuciones. Cambiar el padding redimensiona el cliente y vuelve a
# disparar este hook: con el lock, las reentradas esperan y la ultima corrida
# aplica el tamano final (sin perder el ultimo resize). Ademas protege la
# calibracion. Espera acotada para no colgarse si algo queda trabado.
if command -v flock >/dev/null 2>&1; then
    exec 9>"$RUNTIME/lock"
    flock -w 5 9 || exit 0
fi

# ── Entorno de kitty del cliente (una lectura de /proc) ──
# Setea K_LISTEN / K_KEY / K_WIN del pid dado. Devuelve 1 si no aplica.
kitty_env() {
    K_LISTEN="" K_KEY="" K_WIN=""
    [[ -r "/proc/$1/environ" ]] || return 1
    local out
    out=$(tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null | awk '
        /^KITTY_LISTEN_ON=/{l=substr($0,17)}
        /^KITTY_PUBLIC_KEY=/{k=substr($0,18)}
        /^KITTY_WINDOW_ID=/{w=substr($0,17)}
        END{ if(l==""||w=="") exit 1; printf "%s\t%s\t%s\n",l,k,w }') || return 1
    IFS=$'\t' read -r K_LISTEN K_KEY K_WIN <<<"$out"
    [[ -n "$K_LISTEN" && -n "$K_WIN" ]]
}

kitty_set_pad() { # pad
    KITTY_LISTEN_ON="$K_LISTEN" KITTY_PUBLIC_KEY="$K_KEY" \
        kitten @ set-spacing --match "id:$K_WIN" "padding-h=$1" >/dev/null 2>&1
}

kitty_cols() { # -> columnas actuales del window kitty
    KITTY_LISTEN_ON="$K_LISTEN" KITTY_PUBLIC_KEY="$K_KEY" \
        kitten @ ls --match "id:$K_WIN" 2>/dev/null \
        | grep -m1 '"columns"' | grep -o '[0-9]\+' | head -1
}

# ── Calibracion: columnas que quita cada unidad de padding ──
# Requiere K_LISTEN/K_KEY/K_WIN ya seteados.
calibrate_ratio() {
    local c0 c1
    kitty_set_pad 0;   sleep 0.12; c0=$(kitty_cols)
    kitty_set_pad 100; sleep 0.12; c1=$(kitty_cols)
    if [[ "$c0" =~ ^[0-9]+$ && "$c1" =~ ^[0-9]+$ ]] && (( c0 > c1 )); then
        awk -v a="$c0" -v b="$c1" 'BEGIN{printf "%.4f", (a-b)/100}'
    else
        echo "0.3"
    fi
}

# ── Padding de lectura: el justo para dejar READ_COLS columnas de texto ──
# Requiere K_LISTEN/K_KEY/K_WIN seteados y $ratio.
reading_pad() {
    local skey="${K_LISTEN##*/}-$K_WIN" cnow last
    cnow=$(kitty_cols)
    [[ "$cnow" =~ ^[0-9]+$ ]] || return 1

    if [[ -f "$RUNTIME/pad-$skey" ]]; then
        last=$(cat "$RUNTIME/pad-$skey" 2>/dev/null)
    else
        # Primera vez con esta ventana: baseline limpio (padding 0).
        kitty_set_pad 0
        sleep 0.1
        cnow=$(kitty_cols)
        [[ "$cnow" =~ ^[0-9]+$ ]] || return 1
        last=0
    fi
    [[ "$last" =~ ^[0-9]+$ ]] || last=0

    awk -v c="$cnow" -v r="$ratio" -v last="$last" \
        -v t="$READ_COLS" -v cap="$READ_PAD" 'BEGIN{
            u = c + r*last;          # columnas sin padding
            p = (u - t)/r;           # padding para llegar a la columna objetivo
            if (p < 0) p = 0;
            if (p > cap) p = cap;
            printf "%d", p + 0.5;
        }'
}

# ── Ratio: env > cache > calibracion perezosa ──
ratio="${TMUX_READ_RATIO:-}"
[[ -n "$ratio" ]] || ratio=$(cat "$RATIO_FILE" 2>/dev/null || true)

# Un cliente por linea: nombre, pid, nro de paneles del window que muestra,
# e id de ese window.
calibrated=0
while IFS=$'\t' read -r name pid panes curwin; do
    [[ -n "$name" ]] || continue
    if [[ -n "$TARGET" && "$curwin" != "$TARGET" ]]; then
        continue
    fi
    # Hold: alguien (ej. tmux-newpane.sh) necesita ancho completo fijo; no tocar.
    if [[ "$(tmux show-option -wqv -t "$curwin" @readwidth_hold 2>/dev/null)" == "1" ]]; then
        continue
    fi
    kitty_env "$pid" || continue

    # Calibrar una sola vez, con el primer cliente accesible.
    if [[ -z "$ratio" && "$calibrated" == 0 ]]; then
        ratio=$(calibrate_ratio)
        [[ -n "$ratio" ]] || ratio="0.3"
        printf '%s' "$ratio" > "$RATIO_FILE" 2>/dev/null || true
        calibrated=1
    fi

    case "$MODE" in
        normal)  pad="$NORMAL_PAD" ;;
        reading) pad=$(reading_pad) ;;
        *)       if (( panes <= 1 )); then pad=$(reading_pad); else pad="$NORMAL_PAD"; fi ;;
    esac
    [[ "$pad" =~ ^[0-9]+$ ]] || pad="$NORMAL_PAD"

    kitty_set_pad "$pad"
    printf '%s' "$pad" > "$RUNTIME/pad-${K_LISTEN##*/}-$K_WIN" 2>/dev/null || true
done < <(tmux list-clients -F '#{client_name}	#{client_pid}	#{window_panes}	#{window_id}' 2>/dev/null)
