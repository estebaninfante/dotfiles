#!/usr/bin/env bash
# Auto-sync dotfiles: pull (ff-only) + commit + push + rebuild si hay cambios.
# Seguro: no pushea secrets, ff-only pull, skip si conflicto.
set -euo pipefail

DOTFILES="$HOME/dotfiles"
cd "$DOTFILES"

# ── Detectar machine type ──────────────────────────────────────
MACHINE=$(cat ~/.config/machine-type 2>/dev/null || hostname -s)

# ── 1. Pull (fast-forward only) ────────────────────────────────
PULL_OUTPUT=""
if git remote -v | grep -q .; then
  PULL_OUTPUT=$(git pull --ff-only 2>&1) || {
    echo "[SKIP] Pull fallo (conflicto?). Resuelve manual."
    exit 0
  }
fi

# ── 2. Detectar si hubo cambios ────────────────────────────────
HUBO_CAMBIOS=false
if echo "$PULL_OUTPUT" | grep -qv "^Already up to date"; then
  HUBO_CAMBIOS=true
fi

# ── 3. Check si hay cambios locales ────────────────────────────
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  # No hay nada que commitear, pero pudo haber cambios en pull
  if [ "$HUBO_CAMBIOS" = true ]; then
    echo "[PULL OK] Cambios recibidos. Rebuild..."
    sudo nixos-rebuild switch --flake "$DOTFILES#$MACHINE" 2>&1 | tail -5
    echo "[REBUILD OK] Aplicado."
  fi
  exit 0
fi

# ── 4. Stage cambios ───────────────────────────────────────────
git add -A

# ── 5. Safety: detectar archivos sensibles en el stage ─────────
SENSITIVE_PATTERNS=(
  "*.pem" "*.key" "*.env" ".env"
  "*password*" "*token*" "*secret*"
  "*.p12" "*.pfx" "*.jks"
)

for pattern in "${SENSITIVE_PATTERNS[@]}"; do
  # shellcheck disable=SC2086
  if git diff --cached --name-only | grep -qi $pattern; then
    echo "[SKIP] Archivo sensible detectado en stage: $pattern"
    echo "[SKIP] No se hace commit. Revisa manualmente."
    git reset HEAD -- . 2>/dev/null
    exit 1
  fi
done

# ── 6. Commit ─────────────────────────────────────────────────
CHANGED=$(git diff --cached --stat | tail -1)
TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
git commit -m "auto: $TIMESTAMP | $CHANGED" --no-verify

# ── 7. Push ────────────────────────────────────────────────────
if git remote -v | grep -q .; then
  if ! git push 2>/dev/null; then
    echo "[WARN] Push fallo. Commit local hecho; resuelve manual."
    exit 0
  fi
fi

# ── 8. Rebuild si hubo cambios (locales o remotos) ─────────────
if [ "$HUBO_CAMBIOS" = true ] || [ -n "$CHANGED" ]; then
  echo "[REBUILD] Cambios detectados. Rebuilding..."
  sudo nixos-rebuild switch --flake "$DOTFILES#$MACHINE" 2>&1 | tail -5
  echo "[REBUILD OK] Aplicado."
fi

echo "[OK] Sync completado."
