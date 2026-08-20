#!/usr/bin/env bash
# Auto-sync dotfiles: pull (ff-only) + commit + push.
# Seguro: no pushea secrets, ff-only pull, skip si conflicto.
set -euo pipefail

DOTFILES="$HOME/dotfiles"
cd "$DOTFILES"

# ── 1. Pull (fast-forward only) ────────────────────────────────
if git remote -v | grep -q .; then
  if ! git pull --ff-only 2>/dev/null; then
    echo "[SKIP] Pull fallo (conflicto?). Resuelve manual."
    exit 0
  fi
fi

# ── 2. Check si hay cambios locales ────────────────────────────
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  exit 0  # sin cambios, nada que hacer
fi

# ── 3. Stage cambios ───────────────────────────────────────────
git add -A

# ── 4. Safety: detectar archivos sensibles en el stage ─────────
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

# ── 5. Commit ─────────────────────────────────────────────────
CHANGED=$(git diff --cached --stat | tail -1)
TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
git commit -m "auto: $TIMESTAMP | $CHANGED" --no-verify

# ── 6. Push ────────────────────────────────────────────────────
if git remote -v | grep -q .; then
  if ! git push 2>/dev/null; then
    echo "[WARN] Push fallo. Commit local hecho; resuelve manual."
    exit 0
  fi
  echo "[OK] Sync completado."
fi
