#!/usr/bin/env bash
# ── setup-packages.sh ──
# Instala TODO desde cero: repos, dnf, flatpak, pip, wallpapers.
# Uso: bash setup-packages.sh [--dry-run]
set -euo pipefail

DOTFILES="$HOME/dotfiles"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

info()  { echo -e "  [INFO]  $*"; }
ok()    { echo -e "  [OK]    $*"; }
warn()  { echo -e "  [WARN]  $*"; }
skip()  { echo -e "  [SKIP]  $*"; }
error() { echo -e "  [ERROR] $*"; }
run() {
  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] $*"
  else
    "$@"
  fi
}

PACKAGES_DIR="$DOTFILES/linux/packages"

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  setup-packages.sh                     ║"
echo "║  Instalación completa desde cero       ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ── 1. Repositorios ──
if [ -f "$PACKAGES_DIR/repos.sh" ]; then
  info "Paso 1/7: Agregando repositorios..."
  bash "$PACKAGES_DIR/repos.sh"
  ok "Repositorios listos"
else
  warn "Saltando repos — no se encontró $PACKAGES_DIR/repos.sh"
fi
echo ""

# ── 2. DNF packages ──
DNF_LIST="$PACKAGES_DIR/dnf-packages.txt"
if [ -f "$DNF_LIST" ]; then
  info "Paso 2/7: Instalando paquetes DNF..."
  if dnf list installed ffmpeg-free &>/dev/null; then
    info "Removiendo ffmpeg-free (conflicto con ffmpeg de RPM Fusion)..."
    run sudo dnf remove -y ffmpeg-free
  fi
  packages=$(grep -v '^\s*#' "$DNF_LIST" | grep -v '^\s*$' | tr '\n' ' ')
  info "Paquetes: $packages"
  if [ -n "$packages" ]; then
    run sudo dnf install -y $packages
    ok "Paquetes DNF instalados"
  else
    skip "No hay paquetes DNF en la lista"
  fi
else
  warn "Saltando DNF — no se encontró $DNF_LIST"
fi
echo ""

# ── 3. Flatpak ──
FLATPAK_LIST="$PACKAGES_DIR/flatpak-packages.txt"
if [ -f "$FLATPAK_LIST" ]; then
  info "Paso 3/7: Instalando paquetes Flatpak..."
  flatpak_apps=$(grep -v '^\s*#' "$FLATPAK_LIST" | grep -v '^\s*$')
  if [ -n "$flatpak_apps" ]; then
    for app in $flatpak_apps; do
      if flatpak list --app 2>/dev/null | grep -q "$app"; then
        skip "$app ya instalado"
      else
        info "Instalando $app..."
        run flatpak install -y flathub "$app"
      fi
    done
    ok "Paquetes Flatpak instalados"
  else
    skip "No hay paquetes Flatpak en la lista"
  fi
else
  warn "Saltando Flatpak — no se encontró $FLATPAK_LIST"
fi
echo ""

# ── 4. Pip packages ──
PIP_LIST="$PACKAGES_DIR/pip-packages.txt"
if [ -f "$PIP_LIST" ]; then
  info "Paso 4/7: Instalando paquetes pip..."
  pip_packages=$(grep -v '^\s*#' "$PIP_LIST" | grep -v '^\s*$' | tr '\n' ' ')
  if [ -n "$pip_packages" ]; then
    run pip3 install --user $pip_packages
    ok "Paquetes pip instalados"
  else
    skip "No hay paquetes pip en la lista"
  fi
else
  skip "Saltando pip — no se encontró $PIP_LIST"
fi
echo ""

# ── 5. libinput-gestures (git + make) ──
info "Paso 5/7: Instalando libinput-gestures..."
if command -v libinput-gestures &>/dev/null; then
  skip "libinput-gestures ya instalado"
else
  TMP_CLONE=$(mktemp -d)
  run git clone --depth 1 https://github.com/bulletmark/libinput-gestures.git "$TMP_CLONE/libinput-gestures"
  run sudo make -C "$TMP_CLONE/libinput-gestures" install
  rm -rf "$TMP_CLONE"
  ok "libinput-gestures instalado"
fi
echo ""

# ── 6. Grupo input (para libinput-gestures) ──
info "Paso 6/7: Verificando grupo input..."
if id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -qx input; then
  skip "Usuario ya está en grupo input"
else
  run sudo usermod -aG input "$USER"
  ok "Usuario agregado a grupo input (requiere re-login)"
fi
echo ""

# ── 7. Wallpapers ──
WALLPAPER_DIR="$PACKAGES_DIR/wallpaper"
if [ -d "$WALLPAPER_DIR" ] && [ "$(ls -A "$WALLPAPER_DIR" 2>/dev/null)" ]; then
  info "Paso 7/7: Copiando wallpapers a ~/Imágenes/..."
  mkdir -p "$HOME/Imágenes"
  for img in "$WALLPAPER_DIR"/*; do
    name=$(basename "$img")
    if [ -f "$HOME/Imágenes/$name" ]; then
      skip "Wallpaper $name ya existe"
    else
      run cp "$img" "$HOME/Imágenes/$name"
      ok "Wallpaper $name copiado"
    fi
  done
else
  skip "Saltando wallpapers — no hay archivos en $WALLPAPER_DIR"
fi
echo ""

# ── Final ──
echo "════════════════════════════════════════"
echo "  Instalación completada."
echo "  Ejecuta ahora: bash ~/dotfiles/scripts/install.sh"
echo "  Para enlazar tus configuraciones."
echo "════════════════════════════════════════"