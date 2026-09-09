#!/usr/bin/env bash
# handy-voice-bridge.sh - Bridge between Handy STT and voice-loop
# Called by Handy after transcription completes
# Usage: handy-voice-bridge.sh <transcription>

set -euo pipefail

VOICE_DIR="${HOME}/.local/state/voice"
TRANSCRIPT_FILE="${VOICE_DIR}/last-transcript.txt"
VOICE_LOOP="${HOME}/.local/bin/voice-loop.sh"
VOICE_CMD="${HOME}/.local/bin/voice-cmd.sh"
LOG_FILE="${VOICE_DIR}/handy-bridge.log"

mkdir -p "$VOICE_DIR"

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"; }

# Get transcription from argument or clipboard
TRANSCRIPTION="${1:-}"
if [[ -z "$TRANSCRIPTION" ]]; then
    TRANSCRIPTION=$(wl-paste 2>/dev/null || echo "")
fi

if [[ -z "$TRANSCRIPTION" ]]; then
    log "No transcription received"
    exit 1
fi

log "Received: $TRANSCRIPTION"

# Save to file for other consumers
echo "$TRANSCRIPTION" > "$TRANSCRIPT_FILE"

# Check if voice-loop is running
if pgrep -f "voice-loop.sh" >/dev/null 2>&1; then
    log "Voice loop is running, will process via loop"
    exit 0
fi

# Otherwise process directly
if [[ -x "$VOICE_CMD" ]]; then
    log "Processing via voice-cmd.sh"
    "$VOICE_CMD" once "$TRANSCRIPTION" &
    exit $?
fi

# Fallback: direct opencode call
log "Processing via direct opencode call"
local prompt="Eres un agente de computer use para Hyprland. "
prompt+="Traduce este comando de voz a acción: '$TRANSCRIPTION'\n"
prompt+="Responde SOLO con el comando bash exacto."

RESULT=$(echo -e "$prompt" | opencode --agent hyprland-computer-use --headless 2>/dev/null || echo "")

if [[ -n "$RESULT" ]]; then
    CMD=$(echo "$RESULT" | sed 's/```//g' | sed 's/^ *//;s/ *$//' | head -1)
    log "Executing: $CMD"
    eval "$CMD" &
fi

exit 0