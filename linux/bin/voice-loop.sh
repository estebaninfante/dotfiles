#!/usr/bin/env bash
# voice-loop.sh - Continuous voice control loop
# Connects Handy (STT) with opencode headless + Hyprland
# Usage: voice-loop.sh [mode]

set -euo pipefail

VOICE_DIR="${HOME}/.local/state/voice"
PATTERNS_FILE="${HOME}/.config/opencode/patterns.json"
VOICE_CMD="${HOME}/.local/bin/voice-cmd.sh"
LOG_FILE="${VOICE_DIR}/loop.log"
TRANSCRIPT_FILE="${VOICE_DIR}/last-transcript.txt"

mkdir -p "$VOICE_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }
info() { echo -e "${GREEN}[loop]${NC} $*"; }
warn() { echo -e "${YELLOW}[loop]${NC} $*"; }
error() { echo -e "${RED}[loop]${NC} $*" >&2; }
debug() { echo -e "${BLUE}[loop]${NC} $*"; }

# State file for toggle
STATE_FILE="${VOICE_DIR}/loop-state"

# Cleanup on exit
cleanup() {
    info "Deteniendo voice loop..."
    rm -f "$STATE_FILE"
    log "Loop stopped"
    exit 0
}
trap cleanup SIGINT SIGTERM

# Check if loop is running
is_running() {
    [[ -f "$STATE_FILE" ]] && kill -0 "$(cat "$STATE_FILE")" 2>/dev/null
}

# Toggle loop on/off
toggle_loop() {
    if is_running; then
        local pid=$(cat "$STATE_FILE")
        info "Deteniendo loop (PID: $pid)"
        kill "$pid" 2>/dev/null || true
        rm -f "$STATE_FILE"
        return 0
    else
        info "Iniciando loop..."
        $0 run &
        disown
        return 1
    fi
}

# Process a single transcription
process_transcript() {
    local transcript="$1"
    
    if [[ -z "$transcript" ]]; then
        return 1
    fi
    
    log "Processing: $transcript"
    
    # Check for special commands
    case "$transcript" in
        "salir"|"exit"|"quit"|"adiós"|"para")
            info "Comando de salida detectado"
            cleanup
            ;;
        "ayuda"|"help")
            info "Comandos disponibles:"
            echo "  - 'abrir navegador' → Firefox en ws1"
            echo "  - 'abrir terminal' → Kitty"
            echo "  - 'cerrar ventana' → killactive"
            echo "  - 'workspace 1-5' → cambiar workspace"
            echo "  - 'maximizar' → fullscreen"
            echo "  - 'toggle flotante' → floating"
            echo "  - 'copiar/pegar' → ctrl+c/v"
            echo "  - 'capturar pantalla' → grim"
            echo "  - 'salir' → detener loop"
            return 0
            ;;
        "estado"|"status")
            info "Loop activo"
            info "Patrones aprendidos: $(jq '.commands | length' "$PATTERNS_FILE" 2>/dev/null || echo 0)"
            return 0
            ;;
    esac
    
    # Try voice-cmd.sh
    if [[ -x "$VOICE_CMD" ]]; then
        "$VOICE_CMD" once "$transcript"
        return $?
    fi
    
    # Fallback: direct opencode call
    local prompt="Eres un agente de computer use para Hyprland. "
    prompt+="Traduce este comando de voz a acción: '$transcript'\n"
    prompt+="Responde SOLO con el comando bash exacto a ejecutar."
    
    local result=$(echo -e "$prompt" | opencode --agent hyprland-computer-use --headless 2>/dev/null || echo "")
    
    if [[ -n "$result" ]]; then
        local cmd=$(echo "$result" | sed 's/```//g' | sed 's/^ *//;s/ *$//' | head -1)
        info "Ejecutando: $cmd"
        eval "$cmd"
        return $?
    fi
    
    error "No se pudo procesar: $transcript"
    return 1
}

# Main run loop
run_loop() {
    local mode="${1:-continuous}"
    
    echo $$ > "$STATE_FILE"
    log "Loop started (PID: $$, mode: $mode)"
    
    info "Voice Loop activo - Habla tus comandos"
    info "Ctrl+C o di 'salir' para detener"
    echo ""
    
    while true; do
        # Try to get transcription from Handy
        local transcript=""
        
        # Method 1: Check Handy's output file
        if [[ -f "$TRANSCRIPT_FILE" ]]; then
            local last_mod=$(stat -c %Y "$TRANSCRIPT_FILE" 2>/dev/null || echo 0)
            local now=$(date +%s)
            
            # Only use if recent (last 5 seconds)
            if (( now - last_mod < 5 )); then
                transcript=$(cat "$TRANSCRIPT_FILE" 2>/dev/null || echo "")
            fi
        fi
        
        # Method 2: Listen to Handy's FIFO if exists
        local fifo="/tmp/handy-transcript"
        if [[ -p "$fifo" ]]; then
            timeout 2 cat "$fifo" 2>/dev/null || true
        fi
        
        # Method 3: Manual input fallback
        if [[ -z "$transcript" && "$mode" == "interactive" ]]; then
            echo -ne "${GREEN}[voice]${NC} "
            read -r transcript
        fi
        
        if [[ -n "$transcript" ]]; then
            process_transcript "$transcript"
            echo ""
        fi
        
        sleep 0.2
    done
}

# Run Handy + Loop integration
run_with_handy() {
    info "Iniciando Handy + Voice Loop..."
    
    # Start Handy if not running
    if ! pgrep -x handy >/dev/null; then
        info "Iniciando Handy..."
        handy --start-hidden &
        sleep 2
    fi
    
    # Configure Handy to write transcripts to our file
    # (Handy saves to clipboard by default, we monitor it)
    
    # Start loop
    run_loop continuous
}

# Main
main() {
    local mode="${1:-toggle}"
    
    case "$mode" in
        run|start)
            run_with_handy
            ;;
        stop)
            if is_running; then
                local pid=$(cat "$STATE_FILE")
                info "Deteniendo loop (PID: $pid)"
                kill "$pid" 2>/dev/null || true
                rm -f "$STATE_FILE"
            else
                warn "Loop no está activo"
            fi
            ;;
        toggle)
            toggle_loop
            ;;
        status)
            if is_running; then
                info "Loop activo (PID: $(cat "$STATE_FILE"))"
            else
                info "Loop inactivo"
            fi
            info "Patrones: $(jq '.commands | length' "$PATTERNS_FILE" 2>/dev/null || echo 0)"
            ;;
        once)
            # Single command mode
            local transcript="${2:-}"
            if [[ -z "$transcript" ]]; then
                error "Uso: voice-loop.sh once 'comando de voz'"
                exit 1
            fi
            process_transcript "$transcript"
            ;;
        help)
            echo "Usage: voice-loop.sh [run|stop|toggle|status|once <cmd>|help]"
            echo ""
            echo "Modes:"
            echo "  run/start    - Iniciar loop con Handy"
            echo "  stop         - Detener loop"
            echo "  toggle       - Toggle loop on/off"
            echo "  status       - Mostrar estado"
            echo "  once <cmd>   - Ejecutar un solo comando"
            echo "  help         - Mostrar esta ayuda"
            ;;
        *)
            error "Modo desconocido: $mode"
            main help
            exit 1
            ;;
    esac
}

main "$@"