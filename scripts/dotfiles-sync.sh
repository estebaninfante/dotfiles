#!/usr/bin/env bash
# dotfiles-sync.sh — pull automatico de ~/dotfiles (corre via timer systemd-user).
#
# - No commitea: los cambios locales se preservan con --autostash.
#   Para commitear/pushear cambios propios: scripts/publish.sh
# - Intenta push si hay commits locales nuevos (falla silenciosa si no
#   hay credenciales — tipico en laptop).
# - Flag de pausa: ~/.config/dotfiles-autosync.off (lo crea/borra el
#   menu de la barra: "Dotfiles > Auto-sync")
# - `--force` ignora el flag (usado por "Sync ahora" del menu).
# - `--toggle` pausa/reanuda el auto-sync (usado por el menu de la barra).
set -uo pipefail

REPO="$HOME/dotfiles"
FLAG="$HOME/.config/dotfiles-autosync.off"
LOG="$HOME/.local/state/dotfiles-sync.log"
BRANCH="main"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

mkdir -p "$(dirname "$LOG")" "$(dirname "$FLAG")"

if [[ "${1:-}" == "--toggle" ]]; then
    if [[ -f "$FLAG" ]]; then
        rm -f "$FLAG"
        notify-send -a dotfiles "Dotfiles" "Auto-sync ACTIVADO" 2>/dev/null
    else
        touch "$FLAG"
        notify-send -a dotfiles "Dotfiles" "Auto-sync PAUSADO" 2>/dev/null
    fi
    exit 0
fi

if [[ -f "$FLAG" && $FORCE -eq 0 ]]; then
    exit 0
fi

cd "$REPO" || exit 1

log() { echo "$(date '+%F %T') $*" >>"$LOG"; }

if ! git fetch origin --quiet 2>>"$LOG"; then
    log "WARN fetch fallo (sin red?)"
    exit 0
fi

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/$BRANCH" 2>/dev/null) || { log "WARN sin origin/$BRANCH"; exit 0; }

if [[ "$LOCAL" == "$REMOTE" ]]; then
    exit 0
fi

if ! git pull --rebase --autostash --quiet origin "$BRANCH" 2>>"$LOG"; then
    git rebase --abort >/dev/null 2>&1 || true
    log "ERROR conflicto de rebase — resuelvelo a mano: cd ~/dotfiles && git pull --rebase"
    command -v notify-send >/dev/null && \
        notify-send -u critical "Dotfiles: conflicto de sync" \
            "Resuelve manualmente: cd ~/dotfiles && git pull --rebase" 2>/dev/null
    exit 1
fi

log "OK sync -> $(git rev-parse --short HEAD)"

if [[ -x "$REPO/scripts/omarchy-sync.sh" ]]; then
    if "$REPO/scripts/omarchy-sync.sh" import >>"$LOG" 2>&1; then
        log "OK omarchy import"
    else
        log "WARN omarchy import fallo"
    fi
fi

# Push best-effort: sin credenciales (laptop) falla y se ignora.
if [[ $(git rev-list --count "origin/$BRANCH..HEAD") -gt 0 ]]; then
    if git push --quiet origin "$BRANCH" >>"$LOG" 2>&1; then
        log "OK push"
    else
        log "WARN push fallido (¿sin credenciales?)"
    fi
fi

exit 0
