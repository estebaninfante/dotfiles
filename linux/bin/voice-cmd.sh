#!/usr/bin/env bash
# voice-cmd.sh - Voice command handler for opencode + Hyprland
# Usage: voice-cmd.sh [transcription_file]
# If no file provided, reads from clipboard or stdin

set -euo pipefail

PATTERNS_FILE="${HOME}/.config/opencode/patterns.json"
VOICE_DIR="${HOME}/.local/state/voice"
LOG_FILE="${VOICE_DIR}/voice-cmd.log"

mkdir -p "$VOICE_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }
info() { echo -e "${GREEN}[voice]${NC} $*"; }
warn() { echo -e "${YELLOW}[voice]${NC} $*"; }
error() { echo -e "${RED}[voice]${NC} $*" >&2; }

# Initialize patterns if missing
init_patterns() {
    if [[ ! -f "$PATTERNS_FILE" ]]; then
        cat > "$PATTERNS_FILE" << 'EOF'
{
  "version": 1,
  "commands": {},
  "aliases": {},
  "shortcuts": {}
}
EOF
        log "Initialized patterns file"
    fi
}

# Get transcription from various sources
get_transcription() {
    local input="${1:-}"
    
    if [[ -n "$input" && -f "$input" ]]; then
        cat "$input"
    elif [[ -n "$input" ]]; then
        echo "$input"
    else
        # Try clipboard
        wl-paste 2>/dev/null || xclip -selection clipboard -o 2>/dev/null || echo ""
    fi
}

# Learn from successful command
learn_pattern() {
    local voice_cmd="$1"
    local exec_cmd="$2"
    local success="${3:-true}"
    
    if [[ "$success" != "true" ]]; then
        return
    fi
    
    # Add to patterns
    local tmp=$(mktemp)
    jq --arg v "$voice_cmd" --arg c "$exec_cmd" \
        '.commands[$v] = {"command": $c, "uses": (.commands[$v].uses // 0) + 1, "last_used": now | todate}' \
        "$PATTERNS_FILE" > "$tmp" && mv "$tmp" "$PATTERNS_FILE"
    
    log "Learned: '$voice_cmd' -> '$exec_cmd'"
}

# Check for known pattern
check_pattern() {
    local voice_cmd="$1"
    
    # Direct match
    local known=$(jq -r --arg v "$voice_cmd" '.commands[$v].command // empty' "$PATTERNS_FILE" 2>/dev/null)
    if [[ -n "$known" ]]; then
        echo "$known"
        return 0
    fi
    
    # Alias match
    local alias_cmd=$(jq -r --arg v "$voice_cmd" '.aliases[$v] // empty' "$PATTERNS_FILE" 2>/dev/null)
    if [[ -n "$alias_cmd" ]]; then
        known=$(jq -r --arg v "$alias_cmd" '.commands[$v].command // empty' "$PATTERNS_FILE" 2>/dev/null)
        if [[ -n "$known" ]]; then
            echo "$known"
            return 0
        fi
    fi
    
    # Shortcut match
    local shortcut=$(jq -r --arg v "$voice_cmd" '.shortcuts[$v] // empty' "$PATTERNS_FILE" 2>/dev/null)
    if [[ -n "$shortcut" ]]; then
        echo "$shortcut"
        return 0
    fi
    
    return 1
}

# Execute voice command via opencode
execute_command() {
    local transcription="$1"
    local pattern_found="${2:-}"
    
    # Build context with patterns
    local patterns_context=""
    if [[ -f "$PATTERNS_FILE" ]]; then
        patterns_context=$(jq -r '.commands | to_entries | .[0:10] | .[] | "\(.key) -> \(.value.command)"' "$PATTERNS_FILE" 2>/dev/null || echo "")
    fi
    
    # Create prompt with context
    local prompt="Eres un agente de computer use para Hyprland. "
    prompt+="Traduce este comando de voz a acción concreta: '$transcription'\n\n"
    
    if [[ -n "$patterns_context" ]]; then
        prompt+="Patrones conocidos:\n$patterns_context\n\n"
    fi
    
    prompt+="Responde SOLO con el comando exacto a ejecutar. "
    prompt+="Ejemplo: 'hyprctl dispatch movetoworkspace 5'\n"
    prompt+="Si es un atajo, responde: 'xdotool key super+5'\n"
    prompt+="Si es click: 'xdotool mousemove 500 300 && xdotool click 1'\n"
    
    # Execute via opencode headless
    local result
    result=$(echo -e "$prompt" | opencode --agent hyprland-computer-use --headless 2>/dev/null || echo "")
    
    if [[ -z "$result" ]]; then
        error "No response from opencode"
        return 1
    fi
    
    # Clean response (remove markdown, extra whitespace)
    local cmd=$(echo "$result" | sed 's/```//g' | sed 's/^ *//;s/ *$//' | head -1)
    
    info "Ejecutando: $cmd"
    
    # Execute the command
    if eval "$cmd" 2>/dev/null; then
        info "Comando ejecutado exitosamente"
        learn_pattern "$transcription" "$cmd" "true"
        return 0
    else
        error "Error ejecutando: $cmd"
        return 1
    fi
}

# Interactive mode - continuous listening
interactive_mode() {
    info "Modo interactivo - habla tus comandos"
    info "Ctrl+C para salir"
    
    while true; do
        echo -n "Escuchando... "
        read -r transcription
        
        if [[ -z "$transcription" ]]; then
            continue
        fi
        
        log "Transcription: $transcription"
        
        # Check for exit command
        if [[ "$transcription" =~ ^(salir|exit|quit|adiós)$ ]]; then
            info "Saliendo..."
            break
        fi
        
        # Check for known pattern first
        if pattern=$(check_pattern "$transcription"); then
            info "Patrón conocido: $pattern"
            eval "$pattern" 2>/dev/null && continue
        fi
        
        # Execute via opencode
        execute_command "$transcription"
        
        sleep 0.5
    done
}

# Main
main() {
    init_patterns
    
    local mode="${1:-once}"
    
    case "$mode" in
        once)
            local transcription=$(get_transcription "${2:-}")
            if [[ -z "$transcription" ]]; then
                error "No transcription provided"
                echo "Usage: voice-cmd.sh once '<transcription>'"
                echo "       voice-cmd.sh once /path/to/transcription.txt"
                exit 1
            fi
            
            # Check for known pattern
            if pattern=$(check_pattern "$transcription"); then
                info "Patrón conocido: $pattern"
                eval "$pattern"
            else
                execute_command "$transcription"
            fi
            ;;
            
        interactive|loop)
            interactive_mode
            ;;
            
        learn)
            # Manual pattern learning
            local voice="${2:-}"
            local cmd="${3:-}"
            if [[ -z "$voice" || -z "$cmd" ]]; then
                echo "Usage: voice-cmd.sh learn 'voice command' 'exec command'"
                exit 1
            fi
            learn_pattern "$voice" "$cmd" "true"
            info "Patrón guardado"
            ;;
            
        patterns)
            # Show learned patterns
            jq '.commands | to_entries[] | "\(.key) -> \(.value.command) (used: \(.value.uses))"' "$PATTERNS_FILE" 2>/dev/null
            ;;
            
        *)
            echo "Usage: voice-cmd.sh {once|interactive|learn|patterns} [args]"
            exit 1
            ;;
    esac
}

main "$@"