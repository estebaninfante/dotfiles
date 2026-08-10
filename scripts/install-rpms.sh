#!/usr/bin/env bash
# ── install-rpms.sh ──
# Instala los RPMs locales (handy, opencode-desktop, rstudio) en Fedora.
# En NixOS NO se usa: esos paquetes estan en nixpkgs nativo
# (handy, opencode, opencode-desktop, rstudio) via flake.
#
# Los RPMs NO viven en el repo git (GitHub rechaza >100MB / GH001).
# Se buscan en (en orden):
#   1. $DOTFILES/linux/packages/rpm/   (si los copias ahi)
#   2. ~/Descargas/  y  ~/Downloads/   (donde normalmente los descargas)
#
# Uso: bash install-rpms.sh [--dry-run]
set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

info() { echo -e "  [INFO]  $*"; }
ok()   { echo -e "  [OK]    $*"; }
skip() { echo -e "  [SKIP]  $*"; }
error(){ echo -e "  [ERROR] $*"; }
run() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] $*"
  else
    "$@"
  fi
}

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  install-rpms.sh                       ║"
echo "║  Instala RPMs locales (Fedora)         ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Buscar ubicaciones de RPMs
declare -a SEARCH_DIRS=(
  "$DOTFILES/linux/packages/rpm"
  "$HOME/Descargas"
  "$HOME/Downloads"
)

shopt -s nullglob
rpms=()
for d in "${SEARCH_DIRS[@]}"; do
  [ -d "$d" ] && rpms+=("$d"/*.rpm)
done
shopt -u nullglob

if [ ${#rpms[@]} -eq 0 ]; then
  skip "No se encontraron RPMs en: ${SEARCH_DIRS[*]}"
  echo "  (En NixOS estos paquetes vienen de nixpkgs; no necesitas este script)"
  exit 0
fi

info "RPMs a instalar:"
for r in "${rpms[@]}"; do
  echo "    - $(basename "$r")  [$(dirname "$r")]"
done
echo ""

for r in "${rpms[@]}"; do
  name=$(basename "$r")
  if rpm -q "$(rpm -qp --qf '%{NAME}' "$r" 2>/dev/null)" &>/dev/null; then
    skip "$name ya instalado"
    continue
  fi
  info "Instalando $name..."
  run sudo dnf install -y "$r"
  ok "$name instalado"
done

echo ""
echo "════════════════════════════════════════"
echo "  Listo! RPMs instalados."
echo "════════════════════════════════════════"
