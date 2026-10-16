#!/usr/bin/env bash
# reconcile-machine.sh — aplica a la máquina lo que el repo pide y necesita
# setup (symlinks, paquetes, venv, units). Idempotente.
#
# Lo llama dotfiles-sync.sh cuando cambian las entradas relevantes del repo
# (ver RECONCILE_INPUTS). También se puede correr a mano.
set -uo pipefail

REPO="${HOME}/dotfiles"
LOG="${HOME}/.local/state/dotfiles-reconcile.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "$(date '+%F %T') reconcile: $*" >>"$LOG"; }

log "=== inicio (host: $(hostname -s 2>/dev/null || echo '?')) ==="

if ! bash "$REPO/scripts/link-dotfiles.sh" >>"$LOG" 2>&1; then
    log "link-dotfiles falló"
    exit 1
fi
log "symlinks OK"

if ! bash "$REPO/scripts/setup-kokoro-reader.sh" >>"$LOG" 2>&1; then
    log "setup-kokoro-reader falló"
    exit 1
fi
log "kokoro-reader OK"

log "=== fin OK ==="
notify-send -a dotfiles "Dotfiles" "Setup de maquina aplicado (Kokoro/Zotero)" 2>/dev/null || true
exit 0
