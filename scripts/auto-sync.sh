#!/usr/bin/env bash
# Auto-sync dotfiles: pull (rebase)+ commit + push SIEMPRE (auto-publish) + rebuild seguro.
# Seguro: no pushea secrets, pull --rebase tolera commits locales, aborta en conflicto.
# Rebuild usa SIEMPRE scripts/rebuild.sh (detecta maquina por hardware + valida root UUID).
# Paralelismo controlado: builds CUDA (sunshine NVENC) con max-jobs default OOM/congelan.
# Marker ~/.local/state/dotfiles/skip-auto-rebuild → publish-only, sin rebuild.
set -euo pipefail

DOTFILES="$HOME/dotfiles"
cd "$DOTFILES"

GENERATIONS_TO_KEEP=5
SKIP_REBUILD="$HOME/.local/state/dotfiles/skip-auto-rebuild"

do_rebuild() {
  if [ -f "$SKIP_REBUILD" ]; then
    echo "[REBUILD SKIP] marker $SKIP_REBUILD presente. Solo publish."
    return 0
  fi
  echo "[REBUILD] Aplicando..."
  # max-jobs/cores controlados: build CUDA con paralelismo default congela la maquina.
  export NIX_CONFIG="max-jobs = 2"$'\n'"cores = 8"
  if bash "$DOTFILES/scripts/rebuild.sh" switch 2>&1 | tail -5; then
    echo "[GC] Manteniendo ultimas $GENERATIONS_TO_KEEP generaciones..."
    sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +$GENERATIONS_TO_KEEP 2>/dev/null || true
    sudo nix-collect-garbage -d 2>&1 | tail -2
    echo "[REBUILD OK] Aplicado y limpio."
  else
    echo "[REBUILD FAIL] Revisa manualmente."
  fi
}

# ── 1. Pull con rebase (integra commits locales, no fast-forward estricto) ──
PULL_OUTPUT=""
HUBO_CAMBIOS=false
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