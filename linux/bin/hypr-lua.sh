#!/usr/bin/env bash
# hypr-lua.sh — Wrapper para hyprctl eval + Lua API (Hyprland ≥0.55)
#
# En Lua mode, hyprctl dispatch clásico NO funciona. Todo va por hyprctl eval.
# Este script abstrae la sintaxis Lua para que otros agentes no tengan que conocerla.
#
# Uso:
#   hypr-lua.sh exec "comando"
#   hypr-lua.sh close
#   hypr-lua.sh focus <left|right|up|down>
#   hypr-lua.sh workspace <N>
#   hypr-lua.sh move <N>
#   hypr-lua.sh fullscreen
#   hypr-lua.sh float
#   hypr-lua.sh focus-pid <PID>
#   hypr-lua.sh focus-address < address>
#   hypr-lua.sh open-in-workspace <app> <N> [class_match]
#   hypr-lua.sh clients [class_match]

set -uo pipefail

case "${1:-help}" in
  exec)
    shift
    hyprctl eval "hl.exec_cmd(\"$*\")"
    ;;
  close)
    hyprctl eval "hl.dispatch(hl.dsp.window.close())"
    ;;
  focus)
    dir="${2:-}"
    case "$dir" in
      left|right|up|down)
        hyprctl eval "hl.dispatch(hl.dsp.focus({ direction = '$dir' }))"
        ;;
      *) echo "uso: hypr-lua.sh focus <left|right|up|down>" >&2; exit 2 ;;
    esac
    ;;
  workspace)
    N="${2:?falta workspace}"
    hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = $N }))"
    ;;
  move)
    N="${2:?falta workspace}"
    hyprctl eval "hl.dispatch(hl.dsp.window.move({ workspace = $N }))"
    ;;
  fullscreen)
    hyprctl eval "hl.dispatch(hl.dsp.window.fullscreen())"
    ;;
  float)
    hyprctl eval "hl.dispatch(hl.dsp.window.float({ action = 'toggle' }))"
    ;;
  focus-pid)
    PID="${2:?falta PID}"
    hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'pid:$PID' }))"
    ;;
  focus-address)
    ADDR="${2:?falta address}"
    hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:$ADDR' }))"
    ;;
  open-in-workspace)
    APP="${2:?falta app}"
    WS="${3:?falta workspace}"
    CLASS="${4:-}"
    # Ejecutar app
    hyprctl eval "hl.exec_cmd(\"$APP\")"
    sleep 2
    # Buscar PID por class si se proporcionó, sino usar la ventana activa
    if [ -n "$CLASS" ]; then
      PID=$(hyprctl clients -j | python3 -c "
import sys,json
for c in json.load(sys.stdin):
    if '$CLASS'.lower() in c.get('class','').lower():
        print(c['pid']); break
" 2>/dev/null)
      if [ -n "$PID" ]; then
        hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'pid:$PID' }))"
      fi
    fi
    # Mover a workspace
    hyprctl eval "hl.dispatch(hl.dsp.window.move({ workspace = $WS }))"
    ;;
  clients)
    CLASS="${2:-}"
    if [ -n "$CLASS" ]; then
      hyprctl clients -j | python3 -c "
import sys,json
for c in json.load(sys.stdin):
    if '$CLASS'.lower() in c.get('class','').lower():
        print(f\"pid={c['pid']} addr={c['address']} class={c['class']} title={c.get('title','')}\")
"
    else
      hyprctl clients -j | python3 -c "
import sys,json
for c in json.load(sys.stdin):
    print(f\"pid={c['pid']} addr={c['address']} class={c['class']} title={c.get('title','')}\")
"
    fi
    ;;
  help|*)
    cat <<'EOF'
hypr-lua.sh — Wrapper para hyprctl eval + Lua API

Uso:
  hypr-lua.sh exec "comando"           Ejecutar shell command
  hypr-lua.sh close                    Cerrar ventana activa
  hypr-lua.sh focus <dir>              Focus left/right/up/down
  hypr-lua.sh workspace <N>            Switch a workspace N
  hypr-lua.sh move <N>                 Mover ventana a workspace N
  hypr-lua.sh fullscreen               Toggle fullscreen
  hypr-lua.sh float                    Toggle floating
  hypr-lua.sh focus-pid <PID>          Focus ventana por PID
  hypr-lua.sh focus-address <addr>     Focus ventana por address
  hypr-lua.sh open-in-workspace <app> <N> [class]  Abrir app en workspace
  hypr-lua.sh clients [class]          Listar ventanas (filtrar por class)
EOF
    ;;
esac
