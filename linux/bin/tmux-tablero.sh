#!/usr/bin/env bash
# tmux-tablero.sh — reúne TODAS las sesiones de tmux (una por panel) en una
# sola ventana de kitty, en grilla, como tablero para vigilar varios agentes.
#
# Cada panel muestra EN VIVO otra sesión de tmux mediante un cliente anidado
# (`tmux -f /dev/null attach`). No mueve ni mata nada: las sesiones originales
# y sus procesos quedan intactos; solo se agregan vistas.
#
# En la grilla, ctrl+f agranda a pantalla completa el panel ENFOCADO y repetir
# lo devuelve (ver tmux.conf: `bind -n C-f resize-pane -Z`).
#
# Uso:
#   tmux-tablero.sh             arma el tablero y abre una ventana de kitty
#   tmux-tablero.sh --no-open   solo arma el tablero (sin abrir kitty)
#   tmux-tablero.sh list        lista las sesiones que incluiría
#   tmux-tablero.sh close       cierra el tablero
#
# Config por entorno:
#   TMUX_TABLERO_SESSION   nombre del tablero (default: tablero)
#   TMUX_TABLERO_GRID      grilla "COLSxROWS" o "auto" (default: auto)
#   TMUX_TABLERO_MIN_W     ancho mínimo por panel, en columnas (default 40)
#   TMUX_TABLERO_MIN_H     alto mínimo por panel, en filas (default 9)

set -uo pipefail

DASH="${TMUX_TABLERO_SESSION:-tablero}"
GRID="${TMUX_TABLERO_GRID:-auto}"
MIN_W="${TMUX_TABLERO_MIN_W:-40}"
MIN_H="${TMUX_TABLERO_MIN_H:-9}"
# La terminal del tablero es kitty por defecto. NO usar $TERMINAL: en Omarchy
# apunta a xdg-terminal-exec y puede relanzar la terminal actual (y anidar tmux).
TERM_BIN="${TMUX_TABLERO_TERM:-kitty}"

command -v tmux >/dev/null 2>&1 || { echo "tmux-tablero: falta tmux" >&2; exit 1; }

list_sessions() {
  tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -vx "$DASH"
}

close_dash() {
  local -a pids=() ttys=()
  mapfile -t pids < <(tmux list-panes -t "$DASH:tablero" -F '#{pane_pid}' 2>/dev/null)
  mapfile -t ttys < <(tmux list-panes -t "$DASH:tablero" -F '#{pane_tty}' 2>/dev/null)
  tmux kill-session -t "$DASH" 2>/dev/null || true
  # Los clientes anidados (uno por panel) no mueren solos al cerrar la sesión;
  # se los mata por pid y, por las dudas, por tty (evita huérfanos acumulados).
  local p t cp ct
  for p in ${pids[@]+"${pids[@]}"}; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
  if [ "${#ttys[@]}" -gt 0 ]; then
    while read -r cp ct; do
      for t in "${ttys[@]}"; do
        [ "$ct" = "$t" ] && kill "$cp" 2>/dev/null
      done
    done < <(tmux list-clients -F '#{client_pid} #{client_tty}' 2>/dev/null)
  fi
}

reload_grid() {
  TMUX_MIN_W="$MIN_W" TMUX_MIN_H="$MIN_H" \
    tmux-grid.sh "$GRID" "$DASH:tablero" >/dev/null 2>&1 || true
}

# Etiqueta del panel: "agente · sesión" si la sesión tiene agente registrado.
label_for() {
  local sess="$1" name
  name="$(tmux display-message -p -t "$sess" '#{@agent_name}' 2>/dev/null)"
  if [ -n "$name" ]; then printf '%s · %s' "$name" "$sess"; else printf '%s' "$sess"; fi
}

# Panel más grande de la ventana, y en qué dirección conviene partirlo.
split_target() {
  local id w h area best="" best_area=0 best_w=0 best_h=0
  while read -r id w h; do
    area=$(( w * h ))
    if (( area > best_area )); then best_area=$area; best="$id"; best_w=$w; best_h=$h; fi
  done < <(tmux list-panes -t "$DASH:tablero" -F '#{pane_id} #{pane_width} #{pane_height}' 2>/dev/null)
  [ -n "$best" ] || return 1
  if (( best_w >= best_h )); then printf '%s -h\n' "$best"; else printf '%s -v\n' "$best"; fi
}

case "${1:-}" in
  list)    list_sessions; exit 0 ;;
  close)   close_dash; echo "tablero cerrado"; exit 0 ;;
  --no-open) OPEN=0 ;;
  "")      OPEN=1 ;;
  *)       echo "uso: tmux-tablero.sh [--no-open|list|close]" >&2; exit 2 ;;
esac

mapfile -t sessions < <(list_sessions)
if [ "${#sessions[@]}" -eq 0 ]; then
  echo "tmux-tablero: no hay otras sesiones de tmux" >&2
  exit 0
fi

# Se reconstruye para reflejar el estado actual.
close_dash

# Se construye con una ventana grande: si no, los splits se quedan sin espacio
# antes de llegar a N paneles. El tamaño real lo fija kitty al entrar.
first="${sessions[0]}"
firstpane="$(tmux new-session -d -P -F '#{pane_id}' -x 600 -y 400 -s "$DASH" -n tablero -c "$HOME" \
  "env -u TMUX tmux -f /dev/null attach -t '$first'" 2>/dev/null)"
[ -n "$firstpane" ] && tmux select-pane -t "$firstpane" -T "$(label_for "$first")" 2>/dev/null

for sess in "${sessions[@]:1}"; do
  read -r target dir < <(split_target) || break
  newpane="$(tmux split-window -P -F '#{pane_id}' -t "$target" "$dir" -c "$HOME" \
    "env -u TMUX tmux -f /dev/null attach -t '$sess'" 2>/dev/null)"
  [ -n "$newpane" ] && tmux select-pane -t "$newpane" -T "$(label_for "$sess")" 2>/dev/null
done

tmux set-option -w -t "$DASH:tablero" pane-border-status top 2>/dev/null || true
tmux set-option -w -t "$DASH:tablero" pane-border-format " #{pane_title} " 2>/dev/null || true
tmux set-option -w -t "$DASH:tablero" pane-border-style "fg=#555555" 2>/dev/null || true
tmux set-option -w -t "$DASH:tablero" pane-active-border-style "fg=#aaaaaa" 2>/dev/null || true

# Grilla inicial; se reajusta con el ancho real una vez que kitty entra.
reload_grid
echo "tablero: $(tmux list-panes -t "$DASH:tablero" 2>/dev/null | wc -l) panel(es)"

[ "${OPEN:-0}" = "1" ] || exit 0

# Una sola ventana de kitty con el tablero. Se limpia TMUX (para no anidar la
# terminal actual dentro de tmux) y `</dev/null` evita que herede la terminal
# desde la que se llama.
setsid env -u TMUX "$TERM_BIN" --title "tablero · ${#sessions[@]} paneles" \
  tmux attach -t "$DASH" </dev/null >/dev/null 2>&1 &

# El reajuste al tamaño real corre en segundo plano: no bloquea el comando.
(
  for _ in $(seq 1 100); do
    tmux list-clients -t "$DASH" 2>/dev/null | grep -q . && break
    sleep 0.1
  done
  sleep 0.4
  reload_grid
) >/dev/null 2>&1 &
disown 2>/dev/null || true
