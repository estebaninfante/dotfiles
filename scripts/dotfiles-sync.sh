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
# Si algo falla (conflicto de rebase, push, import), lanza un AGENTE PI
# HEADLESS que lo resuelva en el repo (ver spawn_resolver), con cooldown para
# no loopear.
#
# Flags: --force ignora la pausa; --toggle pausa/reanuda; --resolve [motivo]
#        lanza el resolutor a mano.
# Pausa: ~/.config/dotfiles-autosync.off (menu de la barra: Dotfiles > Auto-sync)
set -uo pipefail

REPO="$HOME/dotfiles"
FLAG="$HOME/.config/dotfiles-autosync.off"
LOG="$HOME/.local/state/dotfiles-sync.log"
BRANCH="main"

# --- Resolutor headless de errores -------------------------------------
RESOLVER_LOCK="$HOME/.local/state/dotfiles-resolver.lock"
RESOLVER_LOG="$HOME/.local/state/dotfiles-resolver.log"
RESOLVER_COOLDOWN="${DOTFILES_SYNC_RESOLVER_COOLDOWN:-1800}"  # segundos entre intentos
RESOLVER_TIMEOUT="${DOTFILES_SYNC_RESOLVER_TIMEOUT:-900}"     # segundos máx del agente
RESOLVER_MODEL="${DOTFILES_SYNC_AGENT_MODEL:-}"               # vacío = modelo por defecto de Pi

log() { echo "$(date '+%F %T') $*" >>"$LOG"; }

# spawn_resolver <motivo>: deja el repo en manos de un agente Pi headless que
# resuelve el conflicto y vuelve a commitear/pushear. Cooldown para que, si el
# agente no puede, no se relance en bucle cada 5 minutos.
spawn_resolver() {
    local reason="${1:-error de sync}"
    mkdir -p "$(dirname "$RESOLVER_LOG")"
    if [[ -f "$RESOLVER_LOCK" ]]; then
        local age
        age=$(( $(date +%s) - $(stat -c %Y "$RESOLVER_LOCK" 2>/dev/null || echo 0) ))
        if (( age < RESOLVER_COOLDOWN )); then
            log "resolver: en cooldown (${age}s < ${RESOLVER_COOLDOWN}s), omitido"
            return 0
        fi
    fi
    touch "$RESOLVER_LOCK"

    local prompt
    prompt="Fallo de sincronizacion automatica de dotfiles.
- Repositorio: $REPO (rama $BRANCH).
- Motivo: $reason.

Resolvelo sin pedir confirmacion:
1. Corre 'git status' y revisa si quedo un rebase o merge a medias.
2. Resolve el conflicto respetando los cambios de las dos maquinas; no descartes cambios ajenos sin criterio.
3. Deja el arbol limpio, con 'origin/$BRANCH' integrado, y termina con commit + 'git push origin $BRANCH'.
4. No dejes el repo a mitad de un rebase ni con cambios sin commitear.
Al final, resume en una linea que hiciste."

    local args=(--print --no-session --approve --thinking medium
                --tools bash,read,edit,write)
    [[ -n "$RESOLVER_MODEL" ]] && args+=(--model "$RESOLVER_MODEL")

    log "resolver: lanzando agente headless ($reason)"
    ( cd "$REPO" && timeout "$RESOLVER_TIMEOUT" pi "${args[@]}" "$prompt" ) >>"$RESOLVER_LOG" 2>&1
    local rc=$?
    log "resolver: termino rc=$rc"
    if (( rc == 0 )); then
        notify-send -a dotfiles "Dotfiles" "Un agente resolvio el error de sync" 2>/dev/null
    else
        notify-send -u critical -a dotfiles "Dotfiles: sync sin resolver" "Revisa $RESOLVER_LOG" 2>/dev/null
    fi
}

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

# Un solo sync a la vez. El timer (cada ~5 min) y una corrida manual (--force,
# que AGENTS.md manda usar) pueden solaparse: el `git fetch` de cada uno reescribe
# el MISMO .git/FETCH_HEAD y la pull siguiente ve dos "merge heads" -> git muere
# con "Cannot rebase onto multiple branches." (run_rebase, builtin/pull.c). La
# carrera tambien puede pisar un rebase en curso. Si ya hay uno corriendo, se
# omite esta pasada; la que corre deja el repo al dia.
RUN_LOCK="$HOME/.local/state/dotfiles-sync.lock"
exec 9>"$RUN_LOCK"
if ! flock -n 9; then
    log "otro sync en curso — corrida omitida"
    exit 0
fi

if [[ "${1:-}" == "--resolve" ]]; then
    shift
    spawn_resolver "${*:-prueba manual}"
    exit 0
fi

if [[ -f "$FLAG" && $FORCE -eq 0 ]]; then
    exit 0
fi

cd "$REPO" || { spawn_resolver "no existe el repo $REPO"; exit 1; }
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
    if ! "$REPO/scripts/omarchy-sync.sh" export >>"$LOG" 2>&1; then
        log "WARN export omarchy fallo"
        spawn_resolver "fallo el export de ~/.config/omarchy al repo"
        exit 1
    fi
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
        log "ERROR conflicto de rebase — llamado al resolutor"
        notify-send -u critical "Dotfiles: conflicto de sync" \
            "Un agente headless va a intentar resolverlo" 2>/dev/null
        spawn_resolver "conflicto de rebase al integrar origin/$BRANCH"
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
        log "WARN omarchy import fallo — llamado al resolutor"
        spawn_resolver "fallo el import del repo a la config viva de Omarchy"
        exit 1
    fi
fi

# 5) Subir.
if [[ "$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo 0)" -gt 0 ]]; then
    if git push --quiet origin "$BRANCH" >>"$LOG" 2>&1; then
        log "OK push"
    else
        log "WARN push fallido — llamado al resolutor"
        spawn_resolver "git push fallido (¿credenciales? ¿divergencia?)"
        exit 1
    fi
fi

exit 0
