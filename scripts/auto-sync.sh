#!/usr/bin/env bash
# Auto-sync dotfiles: pull (rebase)+ commit + push SIEMPRE (auto-publish) + rebuild seguro.
# Seguro: no pushea secrets, pull --rebase tolera commits locales, aborta en conflicto.
# Rebuild usa SIEMPRE scripts/rebuild.sh (detecta maquina por hardware + valida root UUID).
# Paralelismo BAJO por defecto (max-jobs=2, cores=4; override con AUTO_SYNC_MAX_JOBS/
# AUTO_SYNC_CORES): el default (auto=24) congela la maquina en builds CUDA.
# Watchdog: avisa por ntfy (opencode-$machine) si el rebuild se demora (>10min,
# re-aviso 1h) o se estanca sin output (>20min). Log: ~/.local/state/dotfiles/auto-build.log.
# Marker ~/.local/state/dotfiles/skip-auto-rebuild → publish-only, sin rebuild.
set -euo pipefail

DOTFILES="$HOME/dotfiles"
cd "$DOTFILES"

GENERATIONS_TO_KEEP=5
SKIP_REBUILD="$HOME/.local/state/dotfiles/skip-auto-rebuild"
STATE_DIR="$HOME/.local/state/dotfiles"
BUILD_LOG="$STATE_DIR/auto-build.log"

# Tipeo ntfy por maquina (patron notify-sound): opencode-desktop / opencode-laptop
machine_topic() {
  local m
  m="$(cat "$HOME/.config/machine-type" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$m" ] || m="desktop"
  echo "opencode-$m"
}

# Push ntfy (fail silencioso si no hay red). $1=title $2=priority $3=message
notify() {
  curl --fail --silent --show-error --max-time 5 --connect-timeout 2 \
    -X POST "https://ntfy.sh/$(machine_topic)" \
    -H "Title: $1" -H "Priority: $2" -H "Tags: warning" \
    --data-raw "$3" >/dev/null 2>&1 || true
}

do_rebuild() {
  if [ -f "$SKIP_REBUILD" ]; then
    echo "[REBUILD SKIP] marker $SKIP_REBUILD presente. Solo publish."
    return 0
  fi

  # Paralelismo BAJO por defecto: el default (auto=24) saturo/congelo la
  # maquina durante el build CUDA. Override opcional via env:
  #   AUTO_SYNC_MAX_JOBS / AUTO_SYNC_CORES
  local max_jobs="${AUTO_SYNC_MAX_JOBS:-2}"
  local cores="${AUTO_SYNC_CORES:-4}"
  export NIX_CONFIG="max-jobs = $max_jobs"$'\n'"cores = $cores"
  local warn_total_min="${REBUILD_WARN_MIN:-10}"
  local warn_stall_min="${REBUILD_STALL_MIN:-20}"

  mkdir -p "$STATE_DIR"
  : > "$BUILD_LOG"
  echo "[REBUILD] Aplicando (max-jobs=$max_jobs cores=$cores, log=$BUILD_LOG)..."

  bash "$DOTFILES/scripts/rebuild.sh" switch >>"$BUILD_LOG" 2>&1 &
  local bpid=$!
  local start=$SECONDS last_seen=$SECONDS last_line=""
  local warned_total=false warned_stall=false last_total_warn=0

  # Watchdog: avisa por ntfy si el rebuild se demora o se estanca sin output.
  while kill -0 "$bpid" 2>/dev/null; do
    sleep 60
    local now=$SECONDS cur_line
    cur_line="$(grep -v '^$' "$BUILD_LOG" 2>/dev/null | tail -1 || true)"
    if [ "$cur_line" != "$last_line" ]; then
      last_line="$cur_line"
      last_seen=$now
      warned_stall=false
    fi
    if [ -n "$last_line" ] && [ $((now - last_seen)) -ge $((warn_stall_min * 60)) ] && [ "$warned_stall" = false ]; then
      notify "Rebuild estancado >${warn_stall_min}min" 4 "Sin salida nueva (PID $bpid): ${last_line:0:200}"
      warned_stall=true
    fi
    # Demora total: avisa al superar warn_total_min y re-avisa cada hora.
    if [ $((now - start)) -ge $((warn_total_min * 60)) ]; then
      if [ "$warned_total" = false ] || [ $((now - last_total_warn)) -ge 3600 ]; then
        notify "Rebuild >${warn_total_min}min" 3 "Sigue activo (PID $bpid): ${last_line:0:200}"
        warned_total=true
        last_total_warn=$now
      fi
    fi
  done

  local elapsed=$((SECONDS - start))
  local mins=$((elapsed / 60))

  if wait "$bpid"; then
    echo "[GC] Manteniendo ultimas $GENERATIONS_TO_KEEP generaciones..."
    sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +$GENERATIONS_TO_KEEP 2>/dev/null || true
    sudo nix-collect-garbage -d 2>&1 | tail -2
    notify "Rebuild OK" 1 "Aplicado en ${mins}min ${elapsed}s."
    echo "[REBUILD OK] Aplicado y limpio (${mins}min)."
  else
    notify "Rebuild FALLO" 4 "En ${mins}min. Tail del log: $(tail -c 300 "$BUILD_LOG")"
    echo "[REBUILD FAIL] Revisa $BUILD_LOG." >&2
  fi
}

# ── 1. Pull con rebase (integra commits locales, no fast-forward estricto) ──
PULL_OUTPUT=""
HUBO_CAMBIOS=false
PRE_PULL_HEAD="$(git rev-parse HEAD 2>/dev/null || echo "")"
if git remote -v | grep -q .; then
  if PULL_OUTPUT=$(git pull --rebase --autostash 2>&1); then
    if ! echo "$PULL_OUTPUT" | grep -qi "actualizado\|up to date"; then
      HUBO_CAMBIOS=true
    fi
  else
    echo "[PULL CONFLICT] Rebase fallo; abortando para dejar el repo intacto." >&2
    git rebase --abort 2>/dev/null || true
    git status --short >&2
    echo "[SKIP] Resuelve el conflicto manualmente." >&2
    exit 1
  fi
fi

# ── 1b. Reload Hyprland si cambiaron configs (evita error transitorio de inotify) ──
if [ "$HUBO_CAMBIOS" = true ] && [ -n "$PRE_PULL_HEAD" ]; then
  POST_PULL_HEAD="$(git rev-parse HEAD 2>/dev/null || echo "")"
  if [ -n "$POST_PULL_HEAD" ] && [ "$PRE_PULL_HEAD" != "$POST_PULL_HEAD" ]; then
    if git diff --name-only "$PRE_PULL_HEAD" "$POST_PULL_HEAD" 2>/dev/null | grep -q '^linux/config/hypr/'; then
      hyprctl reload 2>/dev/null || true
    fi
  fi
fi

# ── 2. Commit local SIEMPRE (auto-publish) ──
CHANGED=""
if ! git diff --quiet || ! git diff --cached --quiet \
   || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  git add -A

  SENSITIVE_PATTERNS=(
    "*.pem" "*.key" "*.env" ".env"
    "*password*" "*token*" "*secret*"
    "*.p12" "*.pfx" "*.jks"
  )
  for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    # shellcheck disable=SC2086
    if git diff --cached --name-only | grep -qi $pattern; then
      echo "[SKIP] Archivo sensible detectado en stage: $pattern" >&2
      git reset HEAD -- . 2>/dev/null
      exit 1
    fi
  done

  CHANGED=$(git diff --cached --stat | tail -1)
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
  git commit -m "auto: $TIMESTAMP | $CHANGED" --no-verify
fi

# ── 3. Push SIEMPRE los commits nuevos ──
if git remote -v | grep -q . && [ "$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)" -gt 0 ]; then
  if git push 2>/dev/null; then
    echo "[PUSH OK]"
  else
    echo "[WARN] Push fallo. Commit local hecho; resuelve manual." >&2
    exit 0
  fi
fi

# ── 4. Rebuild + GC cuando hubo cambios ──
if [ "$HUBO_CAMBIOS" = true ] || [ -n "$CHANGED" ]; then
  do_rebuild
fi

echo "[OK] Sync completado."