#!/usr/bin/env bash
# setup-wake.sh — wake-word local ("dime") via talk-command + ASR.
#
# Deja funcionando el escucha continua que dispara el buzón de voz:
#   "dime"  ->  ~/.local/bin/voice play-inbox
#
# Motor ASR: selector `voice-asr-stream` (GPU si hay `[wake] gpu_command` y
# conviene por energía; CPU con Vosk si no). Este script prepara la pata CPU
# (venv + vosk + modelo), instala el servicio de usuario y lo habilita.
#
# Uso:  scripts/setup-wake.sh
# Variables: VOICE_ASR_VENV, TALK_COMMAND_REPO.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASR_VENV="${VOICE_ASR_VENV:-$HOME/.local/share/voice/asr-venv}"
ASR_DIR="$HOME/.local/share/voice/asr"
MODEL="$ASR_DIR/vosk-model-small-es-0.42"
MODEL_URL="https://alphacephei.com/vosk/models/vosk-model-small-es-0.42.zip"
TALK_REPO="${TALK_COMMAND_REPO:-$HOME/developing/talk-command}"
SYSTEMD_DIR="$HOME/.config/systemd/user"

command -v uv >/dev/null 2>&1 || { echo "setup-wake: falta 'uv'"; exit 1; }
[ -x "$TALK_REPO/.venv/bin/talk-command" ] || {
    echo "setup-wake: no existe $TALK_REPO/.venv/bin/talk-command"
    echo "  corre primero: cd $TALK_REPO && uv sync"
    exit 1
}

# 1) Venv propio para el ASR (no ensucia el proyecto talk-command).
if [ ! -x "$ASR_VENV/bin/python" ]; then
    uv venv --python 3.12 "$ASR_VENV"
fi
VIRTUAL_ENV="$ASR_VENV" uv pip install -q vosk

# 2) Modelo Vosk chico en español (~58 MB).
mkdir -p "$ASR_DIR"
if [ ! -d "$MODEL" ]; then
    tmp="$(mktemp -d)"
    curl -sSL -o "$tmp/model.zip" "$MODEL_URL"
    unzip -q "$tmp/model.zip" -d "$ASR_DIR"
    rm -rf "$tmp"
fi

# 3) Servicio de usuario (usa el selector voice-asr-stream).
mkdir -p "$SYSTEMD_DIR"
install -m 0644 "$REPO/linux/system/systemd-user/talk-command.service" \
    "$SYSTEMD_DIR/talk-command.service"
systemctl --user daemon-reload
# El servicio vive enmascarado por defecto (ver setup-omarchy.sh); correr
# este script es la forma explícita de volver a habilitarlo.
systemctl --user unmask talk-command.service 2>/dev/null || true
systemctl --user enable --now talk-command.service

echo
echo "wake-word listo. Decí \"dime\" y se lee el buzón."
echo "  estado: systemctl --user status talk-command.service"
echo "  pausar: systemctl --user stop talk-command.service  (o el widget de la barra)"
