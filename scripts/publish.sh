#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$HOME/dotfiles"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  dotfiles publish.sh                   ║"
echo "╚════════════════════════════════════════╝"
echo ""

cd "$DOTFILES"

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "  [ERROR] No es un repositorio Git."
  echo "  Inicializa con: git init && git add -A && git commit -m 'init'"
  exit 1
fi

echo "  git status:"
echo ""
git status
echo ""

if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  echo "  No hay cambios que publicar."
  exit 0
fi

echo "── Anadiendo cambios..."
git add -A

TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
git commit -m "dotfiles: $TIMESTAMP"

echo ""
echo "  Commit creado: $(git log -1 --oneline)"
echo ""

if git remote -v | grep -q .; then
  echo "── Repositorio remoto detectado:"
  git remote -v
  echo ""
  read -r -p "  Ejecutar git push? [y/N] " ans
  if [[ "$ans" =~ ^[Yy]$ ]]; then
    git push
    echo "  Push completado."
  else
    echo "  Push omitido."
  fi
else
  echo "  No hay remoto configurado. Solo commit local."
fi

echo "  Hecho."