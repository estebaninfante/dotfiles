#!/usr/bin/env bash
# brave-cdp.sh — Control Brave via Chrome DevTools Protocol (CDP)
#
# Lanza Brave con --remote-debugging-port si no está corriendo,
# y provee subcomandos para interactuar con páginas web programáticamente.
#
# Uso:
#   brave-cdp.sh restart [url]              # relanzar Brave con CDP
#   brave-cdp.sh tabs                         # listar pestañas
#   brave-cdp.sh open <url>                   # nueva pestaña
#   brave-cdp.sh focus <index>                # enfocar pestaña por índice
#   brave-cdp.sh navigate <index> <url>       # navegar pestaña existente
#   brave-cdp.sh eval <index> <js>            # ejecutar JS en pestaña
#   brave-cdp.sh click <index> <selector>    # clickear elemento CSS
#   brave-cdp.sh type <index> <sel> <text>   # escribir en campo
#   brave-cdp.sh type-enter <index> <sel> <text>  # escribir + Enter
#   brave-cdp.sh read <index> [selector]      # leer texto (full page o selector)
#   brave-cdp.sh screenshot <index> [file]    # captura de pestaña
#   brave-cdp.sh press <index> <key>          # presionar tecla (Enter, Tab, etc.)
#   brave-cdp.sh wait-and-type <url> <sel> <text>  # abrir URL, esperar carga, escribir

set -uo pipefail

CDP_PORT="${CDP_PORT:-9222}"
CDP_HOST="${CDP_HOST:-localhost}"
BRAVE_PROC="brave"
STARTUP_DELAY=3

# ── Python helper para CDP via WebSocket ──
cdp_python() {
  python3 -c "
import asyncio, json, sys, websockets

async def main():
    port = $CDP_PORT
    host = '$CDP_HOST'

    # Obtener lista de tabs
    import urllib.request
    tabs_json = urllib.request.urlopen(f'http://{host}:{port}/json').read()
    tabs = json.loads(tabs_json)

    if not tabs:
        print('ERROR: no hay pestañas abiertas', file=sys.stderr)
        sys.exit(1)

    idx = $1  # índice de pestaña (0-based)
    if idx < 0 or idx >= len(tabs):
        print(f'ERROR: índice {idx} fuera de rango (0-{len(tabs)-1})', file=sys.stderr)
        sys.exit(1)

    ws_url = tabs[idx]['webSocketDebuggerUrl']
    if not ws_url:
        print(f'ERROR: pestaña {idx} no tiene WebSocket URL', file=sys.stderr)
        sys.exit(1)

    async with websockets.connect(ws_url, max_size=10*1024*1024) as ws:
        # Enviar comando CDP
        cmd = json.loads('''$2''')
        await ws.send(json.dumps(cmd))

        # Esperar respuesta (puede venir como evento, buscar la que coincida con id)
        cmd_id = cmd.get('id', 1)
        while True:
            resp = json.loads(await ws.recv())
            if resp.get('id') == cmd_id:
                result = resp.get('result', {})
                value = result.get('result', {}).get('value')
                if value is not None:
                    print(value)
                elif 'result' in result:
                    print(json.dumps(result['result'], indent=2, ensure_ascii=False))
                else:
                    print(json.dumps(result, indent=2, ensure_ascii=False))
                break

asyncio.run(main())
" 2>&1
}

# ── Obtener tabs via HTTP ──
get_tabs() {
  curl -s "http://${CDP_HOST}:${CDP_PORT}/json" 2>/dev/null
}

# ── Lanzar Brave con CDP si no está corriendo ──
ensure_brave() {
  if curl -s "http://${CDP_HOST}:${CDP_PORT}/json" >/dev/null 2>&1; then
    return 0  # CDP ya activo
  fi

  # Brave corriendo pero sin CDP — no se puede habilitar sin reiniciar
  if pgrep -f "brave" >/dev/null 2>&1; then
    echo "WARNING: Brave corriendo SIN CDP (--remote-debugging-port)." >&2
    echo "Para habilitar CDP: brave-cdp.sh restart" >&2
    echo "Iniciando nueva instancia con CDP (la actual sigue sin CDP)..." >&2
  fi

  echo "Iniciando Brave con CDP en puerto $CDP_PORT..." >&2
  "$BRAVE_PROC" \
    --remote-debugging-port="$CDP_PORT" \
    --no-first-run \
    --disable-default-apps \
    --disable-popup-blocking \
    --disable-translate \
    --disable-background-timer-throttling \
    --disable-backgrounding-occluded-windows \
    --disable-renderer-backgrounding \
    "$@" &>/dev/null &
  # Esperar a que CDP esté listo
  for i in $(seq 1 20); do
    sleep 0.5
    if curl -s "http://${CDP_HOST}:${CDP_PORT}/json" >/dev/null 2>&1; then
      echo "Brave CDP listo." >&2
      return 0
    fi
  done
  echo "ERROR: Brave no respondió en CDP tras 10s" >&2
  return 1
}

# ── Subcomandos ──

cmd_tabs() {
  ensure_brave || return 1
  get_tabs | python3 -c "
import sys, json
tabs = json.load(sys.stdin)
for i, t in enumerate(tabs):
    title = t.get('title', '(sin título)')
    url = t.get('url', '')
    tid = t.get('id', '')
    print(f'  [{i}] {title}')
    print(f'      {url}')
    print(f'      id={tid}')
"
}

cmd_open() {
  local url="${1:?uso: brave-cdp.sh open <url>}"
  ensure_brave || return 1
  curl -s "http://${CDP_HOST}:${CDP_PORT}/json/new?${url}" | python3 -c "
import sys, json
tab = json.load(sys.stdin)
print(f'Pestaña abierta: {tab.get(\"title\",\"?\")} — {tab.get(\"url\",\"?\")}')
print(f'id={tab.get(\"id\",\"?\")}')
"
}

cmd_focus() {
  local idx="${1:?uso: brave-cdp.sh focus <index>}"
  ensure_brave || return 1
  local tabs_json
  tabs_json=$(get_tabs)
  local tab_id
  tab_id=$(echo "$tabs_json" | python3 -c "
import sys, json
tabs = json.load(sys.stdin)
idx = $idx
if 0 <= idx < len(tabs):
    print(tabs[idx]['id'])
else:
    print('ERROR', file=sys.stderr)
")
  if [ "$tab_id" = "ERROR" ] || [ -z "$tab_id" ]; then
    echo "ERROR: índice $idx fuera de rango" >&2
    return 1
  fi
  curl -s "http://${CDP_HOST}:${CDP_PORT}/json/activate/${tab_id}" >/dev/null
  echo "Pestaña $idx enfocada"
}

cmd_navigate() {
  local idx="${1:?uso: brave-cdp.sh navigate <index> <url>}"
  local url="${2:?falta URL}"
  ensure_brave || return 1
  cdp_python "$idx" "{\"id\":1,\"method\":\"Page.navigate\",\"params\":{\"url\":\"$url\"}}"
}

cmd_eval() {
  local idx="${1:?uso: brave-cdp.sh eval <index> <js>}"
  local js_code="${2:?falta código JS}"
  ensure_brave || return 1
  # Escapar la cadena JS para JSON
  local escaped_js
  escaped_js=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$js_code")
  cdp_python "$idx" "{\"id\":1,\"method\":\"Runtime.evaluate\",\"params\":{\"expression\":$escaped_js,\"returnByValue\":true}}"
}

cmd_click() {
  local idx="${1:?uso: brave-cdp.sh click <index> <selector>}"
  local selector="${2:?falta CSS selector}"
  ensure_brave || return 1
  local js="document.querySelector('${selector}')?.click() || 'elemento no encontrado: ${selector}'"
  local escaped_js
  escaped_js=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$js")
  cdp_python "$idx" "{\"id\":1,\"method\":\"Runtime.evaluate\",\"params\":{\"expression\":$escaped_js,\"returnByValue\":true}}"
}

cmd_type() {
  local idx="${1:?uso: brave-cdp.sh type <index> <selector> <text>}"
  local selector="${2:?falta CSS selector}"
  local text="${3:?falta texto}"
  ensure_brave || return 1
  # Focus en el campo + insertText (funciona mejor que key events para inputs)
  local escaped_text
  escaped_text=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$text")
  local escaped_sel
  escaped_sel=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$selector")
  local js="(function(){var e=document.querySelector(${escaped_sel});if(!e)return 'selector no encontrado: ${selector}';e.focus();e.value='';})()"
  local escaped_js
  escaped_js=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$js")
  cdp_python "$idx" "{\"id\":1,\"method\":\"Runtime.evaluate\",\"params\":{\"expression\":$escaped_js,\"returnByValue\":true}}"
  # Usar Input.insertText para el texto (más fiable que key events)
  cdp_python "$idx" "{\"id\":2,\"method\":\"Input.insertText\",\"params\":{\"text\":$escaped_text}}"
}

cmd_type_enter() {
  local idx="${1:?uso: brave-cdp.sh type-enter <index> <selector> <text>}"
  local selector="${2:?falta CSS selector}"
  local text="${3:?falta texto}"
  cmd_type "$idx" "$selector" "$text"
  sleep 0.3
  cmd_press "$idx" "Enter"
}

cmd_read() {
  local idx="${1:?uso: brave-cdp.sh read <index> [selector]}"
  local selector="${2:-}"
  ensure_brave || return 1
  local js
  if [ -n "$selector" ]; then
    js="document.querySelector('${selector}')?.innerText || 'elemento no encontrado'"
  else
    js="document.body?.innerText || '(sin contenido)'"
  fi
  local escaped_js
  escaped_js=$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$js")
  cdp_python "$idx" "{\"id\":1,\"method\":\"Runtime.evaluate\",\"params\":{\"expression\":$escaped_js,\"returnByValue\":true}}"
}

cmd_screenshot() {
  local idx="${1:?uso: brave-cdp.sh screenshot <index> [file]}"
  local file="${2:-/tmp/brave-screenshot.png}"
  ensure_brave || return 1
  # Obtener screenshot via CDP
  python3 -c "
import asyncio, json, sys, websockets, base64, urllib.request

async def main():
    port = $CDP_PORT
    host = '$CDP_HOST'
    tabs = json.loads(urllib.request.urlopen(f'http://{host}:{port}/json').read())
    idx = $idx
    if idx < 0 or idx >= len(tabs):
        print(f'ERROR: índice fuera de rango', file=sys.stderr)
        sys.exit(1)
    ws_url = tabs[idx]['webSocketDebuggerUrl']
    async with websockets.connect(ws_url, max_size=50*1024*1024) as ws:
        await ws.send(json.dumps({'id':1,'method':'Page.captureScreenshot','params':{'format':'png'}}))
        while True:
            resp = json.loads(await ws.recv())
            if resp.get('id') == 1:
                data = resp.get('result',{}).get('data','')
                if data:
                    with open('$file','wb') as f:
                        f.write(base64.b64decode(data))
                    print(f'Screenshot guardado: $file')
                else:
                    print('ERROR: no se pudo capturar', file=sys.stderr)
                break

asyncio.run(main())
" 2>&1
}

cmd_press() {
  local idx="${1:?uso: brave-cdp.sh press <index> <key>}"
  local key="${2:?falta tecla (Enter, Tab, Escape, etc.)}"
  ensure_brave || return 1

  # Mapear nombres de tecla a código CDP
  local code
  case "$key" in
    Enter) code="Enter";;
    Tab) code="Tab";;
    Escape|Esc) code="Escape";;
    Backspace) code="Backspace";;
    Delete) code="Delete";;
    ArrowUp|Up) code="ArrowUp";;
    ArrowDown|Down) code="ArrowDown";;
    ArrowLeft|Left) code="ArrowLeft";;
    ArrowRight|Right) code="ArrowRight";;
    Home) code="Home";;
    End) code="End";;
    PageUp) code="PageUp";;
    PageDown) code="PageDown";;
    Space) code="Space";;
    F1) code="F1";;
    F2) code="F2";;
    F3) code="F3";;
    F4) code="F4";;
    F5) code="F5";;
    F6) code="F6";;
    F7) code="F7";;
    F8) code="F8";;
    F9) code="F9";;
    F10) code="F10";;
    F11) code="F11";;
    F12) code="F12";;
    *) code="$key";;
  esac

  # keyDown + keyUp
  cdp_python "$idx" "{\"id\":1,\"method\":\"Input.dispatchKeyEvent\",\"params\":{\"type\":\"keyDown\",\"code\":\"$code\",\"key\":\"$code\",\"windowsVirtualKeyCode\":0,\"nativeVirtualKeyCode\":0}}"
  cdp_python "$idx" "{\"id\":2,\"method\":\"Input.dispatchKeyEvent\",\"params\":{\"type\":\"keyUp\",\"code\":\"$code\",\"key\":\"$code\",\"windowsVirtualKeyCode\":0,\"nativeVirtualKeyCode\":0}}"
  echo "Tecla '$key' presionada"
}

cmd_wait_and_type() {
  local url="${1:?uso: brave-cdp.sh wait-and-type <url> <selector> <text>}"
  local selector="${2:?falta CSS selector}"
  local text="${3:?falta texto}"
  ensure_brave || return 1

  # Abrir URL en nueva pestaña
  echo "Abriendo $url..." >&2
  local tab_json
  tab_json=$(curl -s "http://${CDP_HOST}:${CDP_PORT}/json/new?${url}")
  local tab_idx
  tab_idx=$(echo "$tab_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")

  # Esperar a que la página cargue
  echo "Esperando carga de página..." >&2
  sleep 3

  # Encontrar el índice de la pestaña
  local tabs_json
  tabs_json=$(get_tabs)
  local idx
  idx=$(echo "$tabs_json" | python3 -c "
import sys, json
tabs = json.load(sys.stdin)
for i, t in enumerate(tabs):
    if t.get('id') == '$tab_idx':
        print(i)
        break
")

  if [ -z "$idx" ]; then
    echo "ERROR: no se pudo encontrar la pestaña" >&2
    return 1
  fi

  # Enfocar pestaña
  cmd_focus "$idx"

  # Esperar a que el selector aparezca (hasta 10s)
  echo "Buscando '$selector'..." >&2
  for i in $(seq 1 20); do
    local found
    found=$(cmd_eval "$idx" "!!document.querySelector('${selector}')")
    if [ "$found" = "True" ] || [ "$found" = "true" ]; then
      echo "Selector encontrado, escribiendo..." >&2
      cmd_type_enter "$idx" "$selector" "$text"
      return 0
    fi
    sleep 0.5
  done

  echo "WARNING: selector '$selector' no encontrado tras 10s" >&2
  return 1
}

# ── Main ──

case "${1:-help}" in
  restart)
    echo "Cerrando Brave..." >&2
    pkill -f "brave" 2>/dev/null
    sleep 2
    echo "Relanzando Brave con CDP..." >&2
    exec bash "$0" open "${2:-https://newtab.com}"
    ;;
  tabs)       shift; cmd_tabs "$@";;
  open)       shift; cmd_open "$@";;
  focus)      shift; cmd_focus "$@";;
  navigate)   shift; cmd_navigate "$@";;
  eval)       shift; cmd_eval "$@";;
  click)      shift; cmd_click "$@";;
  type)       shift; cmd_type "$@";;
  type-enter) shift; cmd_type_enter "$@";;
  read)       shift; cmd_read "$@";;
  screenshot) shift; cmd_screenshot "$@";;
  press)      shift; cmd_press "$@";;
  wait-and-type) shift; cmd_wait_and_type "$@";;
  help|*)
    cat <<'EOF'
brave-cdp.sh — Control Brave via Chrome DevTools Protocol

Requiere: python3, websockets (Python), curl

Uso:
  brave-cdp.sh restart [url]              Relanzar Brave con CDP (mata instancia actual)
  brave-cdp.sh tabs                       Listar pestañas abiertas
  brave-cdp.sh open <url>                 Abrir URL en nueva pestaña
  brave-cdp.sh focus <index>              Enfocar pestaña (índice 0-based)
  brave-cdp.sh navigate <index> <url>     Navegar pestaña existente
  brave-cdp.sh eval <index> <js>          Ejecutar JavaScript
  brave-cdp.sh click <index> <selector>   Clickear elemento CSS
  brave-cdp.sh type <index> <sel> <text>  Escribir en campo (focus+insertText)
  brave-cdp.sh type-enter <index> <sel> <txt>  Escribir + Enter
  brave-cdp.sh read <index> [selector]    Leer texto (full page o selector)
  brave-cdp.sh screenshot <index> [file]  Captura de pestaña (PNG)
  brave-cdp.sh press <index> <key>        Presionar tecla (Enter, Tab, etc.)
  brave-cdp.sh wait-and-type <url> <sel> <txt>  Abrir URL, esperar selector, escribir+Enter

⚠️ CDP requiere Brave lanzado con --remote-debugging-port=9222.
   Si Brave ya está corriendo sin CDP: brave-cdp.sh restart

Ejemplo — preguntar a Grok:
  brave-cdp.sh restart "https://grok.com"
  sleep 3
  brave-cdp.sh type-enter 0 "textarea, [contenteditable]" "hola, ¿qué skills existen?"

Entorno:
  CDP_PORT=9222       Puerto CDP (default: 9222)
  CDP_HOST=localhost  Host CDP (default: localhost)
EOF
    ;;
esac
