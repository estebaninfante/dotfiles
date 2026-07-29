#!/usr/bin/env bash
# ── backup-packages.sh ──
# Captura el estado actual del sistema a los manifiestos.
# Útil ANTES de reinstalar: guarda qué paquetes tenías instalados.
# Uso: bash backup-packages.sh
set -euo pipefail

DOTFILES="$HOME/dotfiles"
PACKAGES_DIR="$DOTFILES/linux/packages"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

info() { echo -e "  [INFO]  $*"; }
ok()   { echo -e "  [OK]    $*"; }
warn() { echo -e "  [WARN]  $*"; }

mkdir -p "$PACKAGES_DIR"
mkdir -p "$BACKUP_DIR"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  backup-packages.sh                    ║"
echo "║  Captura paquetes del sistema actual   ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ── 1. DNF packages ──
info "Respaldando lista de paquetes DNF..."
dnf list installed 2>/dev/null | awk 'NR>1 {print $1}' | sort > "$BACKUP_DIR/dnf-full.txt"
# Versión limpia (solo nombres, sin versión)
sed 's/\.x86_64\|\.noarch\|\.i686//g' "$BACKUP_DIR/dnf-full.txt" | sort -u > "$PACKAGES_DIR/dnf-packages.txt"
ok "DNF: $(wc -l < "$PACKAGES_DIR/dnf-packages.txt") paquetes capturados"
echo ""

# ── 2. Flatpak packages ──
info "Respaldando lista de paquetes Flatpak..."
flatpak list --app 2>/dev/null | awk '{print $2}' | sort > "$PACKAGES_DIR/flatpak-packages.txt"
ok "Flatpak: $(wc -l < "$PACKAGES_DIR/flatpak-packages.txt") aplicaciones capturadas"
echo ""

# ── 3. COPR repos ──
info "Respaldando repositorios COPR activos..."
dnf repolist --enabled 2>/dev/null | grep -i copr | awk '{print $1}' > "$BACKUP_DIR/copr-repos.txt"
ok "COPR: $(wc -l < "$BACKUP_DIR/copr-repos.txt") repos capturados (ver $BACKUP_DIR/copr-repos.txt)"
echo ""

# ── 4. Pip packages (opcional) ──
if command -v pip3 &>/dev/null; then
  info "Respaldando paquetes pip del usuario..."
  pip3 list --user --format=freeze 2>/dev/null > "$PACKAGES_DIR/pip-packages.txt" || true
  ok "Pip: $(wc -l < "$PACKAGES_DIR/pip-packages.txt") paquetes capturados"
else
  warn "pip3 no encontrado — saltando"
fi
echo ""

# ── 5. NPM global packages (opcional) ──
if command -v npm &>/dev/null; then
  info "Respaldando paquetes npm globales..."
  npm list -g --depth=0 2>/dev/null | tail -n +2 > "$BACKUP_DIR/npm-global.txt" || true
  ok "NPM: capturado en $BACKUP_DIR/npm-global.txt"
else
  warn "npm no encontrado — saltando"
fi
echo ""

echo "════════════════════════════════════════"
echo "  Backup completado."
echo "  Manifiestos actualizados en: $PACKAGES_DIR"
echo "  Backup completo en: $BACKUP_DIR"
echo "  Revisa los archivos y edita manualmente"
echo "  lo que quieras conservar/eliminar."
echo "════════════════════════════════════════"