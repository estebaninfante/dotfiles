#!/usr/bin/env bash
# ── fresh-install.sh ──
# Instala TODO desde cero en una máquina nueva Fedora.
# Uso: bash fresh-install.sh [--dry-run]
set -euo pipefail

DOTFILES="$HOME/dotfiles"
PACKAGES_DIR="$DOTFILES/linux/packages"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ── Helpers (definidos primero) ──
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

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  fresh-install.sh                      ║"
echo "║  Instalación completa desde cero       ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ── 0. Machine type ──
MACHINE_FILE="$HOME/.config/machine-type"
if [ ! -f "$MACHINE_FILE" ]; then
  echo "  ¿Qué máquina estás configurando?"
  echo "    1) laptop"
  echo "    2) desktop"
  read -r -p "  Elige [1/2]: " choice
  case "$choice" in
    1) echo -n "laptop" > "$MACHINE_FILE" ;;
    2) echo -n "desktop" > "$MACHINE_FILE" ;;
    *) echo "  Opción inválida. Creando 'laptop' por defecto."
       echo -n "laptop" > "$MACHINE_FILE" ;;
  esac
  ok "Machine type: $(cat "$MACHINE_FILE")"
fi
echo ""

# ── 1. Repositorios ──
info "Paso 1/8: Agregando repositorios..."
if [ -f "$PACKAGES_DIR/repos.sh" ]; then
  run bash "$PACKAGES_DIR/repos.sh"
  ok "Repositorios listos"
else
  warn "No se encontró repos.sh — saltando"
fi
echo ""

# ── 2. DNF packages ──
DNF_LIST="$PACKAGES_DIR/dnf-packages.txt"
if [ -f "$DNF_LIST" ]; then
  info "Paso 2/8: Instalando paquetes DNF..."
  packages=$(awk 'NF && !/^#/' "$DNF_LIST" | tr '\n' ' ')
  if [ -n "$packages" ]; then
    run sudo dnf install -y $packages
    ok "Paquetes DNF instalados"
  else
    skip "No hay paquetes DNF en la lista"
  fi
else
  warn "No se encontró $DNF_LIST — saltando"
fi
echo ""

# ── 3. Flatpak ──
FLATPAK_LIST="$PACKAGES_DIR/flatpak-packages.txt"
if [ -f "$FLATPAK_LIST" ]; then
  info "Paso 3/9: Instalando paquetes Flatpak..."
  flatpak_apps=$(awk 'NF && !/^#/' "$FLATPAK_LIST")
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
  warn "No se encontró $FLATPAK_LIST — saltando"
fi
echo ""

# ── 4. RPMs locales (handy, opencode-desktop, rstudio) ──
info "Paso 4/9: Instalando RPMs locales del repo..."
run bash "$DOTFILES/scripts/install-rpms.sh"
echo ""

# ── 5. Pip packages ──
PIP_LIST="$PACKAGES_DIR/pip-packages.txt"
if [ -f "$PIP_LIST" ]; then
  info "Paso 5/9: Instalando paquetes pip..."
  pip_packages=$(awk 'NF && !/^#/' "$PIP_LIST" | tr '\n' ' ')
  if [ -n "$pip_packages" ]; then
    run pip3 install --user $pip_packages
    ok "Paquetes pip instalados"
  else
    skip "No hay paquetes pip en la lista"
  fi
else
  skip "No se encontró $PIP_LIST — saltando"
fi
echo ""

# ── 6. libinput-gestures ──
info "Paso 6/9: Instalando libinput-gestures..."
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

# ── 6. Grupo input ──
info "Paso 6/9: Verificando grupo input..."
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
  info "Paso 7/9: Copiando wallpapers a ~/Imágenes/..."
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
  skip "No hay wallpapers en $WALLPAPER_DIR"
fi
echo ""

# ── 8. Enlazar configuraciones ──
info "Paso 8/9: Enlazando configuraciones..."
run bash "$DOTFILES/scripts/install.sh" --force
ok "Configuraciones enlazadas"
echo ""

# ── 9. Hermes + opencode (prioridad del usuario) ──
info "Paso 9/9: Hermes + opencode..."
if command -v hermes &>/dev/null || [ -x "$HOME/.hermes/bin/hermes" ]; then
  skip "Hermes ya instalado"
else
  info "Instalando Hermes Agent..."
  run bash -c 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash'
  ok "Hermes instalado (configura con: hermes setup)"
fi
if command -v opencode &>/dev/null; then
  skip "opencode ya instalado"
else
  warn "opencode no esta en dnf-packages.txt — anadelo o instalalo manualmente"
fi
echo ""

# ── Final ──
echo "════════════════════════════════════════"
echo "  Instalación completada!"
echo ""
echo "  Siguientes pasos:"
echo "  1. Recarga shell: exec bash"
echo "  2. Si es laptop, configura touchpad/gestures"
echo "  3. Si es desktop, ajusta monitor en:"
echo "     linux/config/hypr/hyprland.lua (línea ~40)"
echo "  4. Recarga Hyprland: hyprctl reload"
echo "════════════════════════════════════════"
