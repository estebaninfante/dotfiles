#!/usr/bin/env bash
# dotfiles-sync.sh — publica y sincroniza ~/dotfiles (corre via timer systemd-user).
#
# Objetivo: que TODO cambio (aunque este a medias) termine en el repo y en el
# remoto, y que las dos maquinas queden siempre con lo ultimo. Por eso NO se
# importa encima de cambios vivos sin antes exportarlos.
#
# Flujo:
#   1) export  : config viva de Omarchy (~/.config/omarchy) -> repo (aditivo)
#   2) commit  : git add -A + commit automatico (WIP incluido)
#   3) pull    : git pull --rebase --autostash (integra lo del otro equipo)
#   4) import  : repo -> config viva, SOLO si el pull cambio la shell Omarchy
#                (a esta altura lo local ya esta commiteado: nada se pierde)
#   5) push    : sube todo
#
# Si hay conflicto de rebase: aborta, avisa y NO importa (para no pisar nada).
#
# Flag de pausa: ~/.config/dotfiles-autosync.off (lo crea/borra el menu de la
# barra: "Dotfiles > Auto-sync"). `--force` ignora el flag. `--toggle` pausa.
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
HOST="$(hostname -s 2>/dev/null || echo unknown)"

# Hyprland recarga al vuelo si cambia su config vinculada; un reload en medio
# del churn del pull se ve como pantallazo negro. Se silencia y se hace UNA vez.
AUTORELOAD_OFF=0
hypr_ok() { command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; }
pause_hypr_autoreload() { hypr_ok || return 0; hyprctl eval "hl.config({ misc = { disable_autoreload = true } })" >/dev/null 2>&1 && AUTORELOAD_OFF=1; }
resume_hypr_autoreload() { [[ "$AUTORELOAD_OFF" == 1 ]] || return 0; hyprctl eval "hl.config({ misc = { disable_autoreload = false } })" >/dev/null 2>&1 || true; AUTORELOAD_OFF=0; }
trap resume_hypr_autoreload EXIT

# 1) Capturar la config viva de Omarchy en el repo antes de mirar lo remoto.
if [[ -x "$REPO/scripts/omarchy-sync.sh" ]]; then
    "$REPO/scripts/omarchy-sync.sh" export >>"$LOG" 2>&1 || log "WARN export omarchy fallo"
fi

# 2) Commit automatico de todo cambio (WIP incluido). Sin cambios, no commitea.
if [[ -n "$(git status --porcelain)" ]]; then
    git add -A >>"$LOG" 2>&1
    if git commit -m "autosync($HOST): $(date '+%F %T')" >>"$LOG" 2>&1; then
        log "OK commit autosync"
    fi
fi

# 3) Integrar lo remoto.
if ! git fetch origin --quiet 2>>"$LOG"; then
    log "WARN fetch fallo (sin red?)"
    exit 0
fi

REMOTE=$(git rev-parse "origin/$BRANCH" 2>/dev/null) || { log "WARN sin origin/$BRANCH"; exit 0; }
LOCAL=$(git rev-parse HEAD)

pull_changed_omarchy=0
if [[ "$LOCAL" != "$REMOTE" ]]; then
    pause_hypr_autoreload
    before=$(git rev-parse HEAD)
    if ! git pull --rebase=merges --autostash --quiet origin "$BRANCH" 2>>"$LOG"; then
        git rebase --abort >/dev/null 2>&1 || true
        resume_hypr_autoreload
        log "ERROR conflicto de rebase — resuelvelo a mano: cd ~/dotfiles && git pull --rebase=merges"
        command -v notify-send >/dev/null && \
            notify-send -u critical "Dotfiles: conflicto de sync" \
                "Resuelve manualmente: cd ~/dotfiles && git pull --rebase=merges" 2>/dev/null
        exit 1
    fi
    resume_hypr_autoreload
    changed=$(git diff --name-only "$before" HEAD 2>/dev/null || true)
    grep -q '^linux/config/omarchy/' <<<"$changed" && pull_changed_omarchy=1
    if hypr_ok && grep -q '^linux/config/hypr/' <<<"$changed"; then
        hyprctl reload >/dev/null 2>&1 || true
    fi
    log "OK pull -> $(git rev-parse --short HEAD)"
fi

# 4) Aplicar a la config viva lo que vino del otro equipo. Seguro porque lo
#    local ya fue exportado y commiteado en los pasos 1-2.
if [[ "$pull_changed_omarchy" == 1 && -x "$REPO/scripts/omarchy-sync.sh" ]]; then
    if "$REPO/scripts/omarchy-sync.sh" import >>"$LOG" 2>&1; then
        log "OK omarchy import"
    else
        log "WARN omarchy import fallo"
    fi
fi

# 5) Subir.
if [[ "$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)" -gt 0 ]]; then
    if git push --quiet origin "$BRANCH" >>"$LOG" 2>&1; then
        log "OK push"
    else
        log "WARN push fallido (¿sin credenciales?)"
    fi
fi

exit 0
