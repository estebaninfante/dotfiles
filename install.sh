#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$HOME/dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

info()  { echo -e "  [INFO]  $*"; }
ok()    { echo -e "  [OK]    $*"; }
warn()  { echo -e "  [WARN]  $*"; }
skip()  { echo -e "  [SKIP]  $*"; }

backup() {
  local target="$1"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    mkdir -p "$BACKUP_DIR"
    cp -r "$target" "$BACKUP_DIR/"
    warn "Backup guardado: $target -> $BACKUP_DIR/"
  fi
}

link() {
  local src="$1"
  local dst="$2"
  if [ -L "$dst" ]; then
    local current
    current=$(readlink "$dst")
    if [ "$current" = "$src" ]; then
      skip "$dst -> $src (ya existe)"
      return
    else
      warn "Symlink diferente: $dst -> $current (esperado: $src)"
      rm -f "$dst"
    fi
  elif [ -e "$dst" ]; then
    local ans
    read -r -p "  $dst ya existe. Sobrescribir? [y/N] " ans
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
      skip "$dst (omitido por usuario)"
      return
    fi
    backup "$dst"
    rm -rf "$dst"
  fi
  ln -s "$src" "$dst"
  ok "$dst -> $src"
}

link_config() {
  link "$DOTFILES/linux/config/$1" "$HOME/.config/$1"
}

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  dotfiles install.sh                   ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ── Config apps ──────────────────────────────────────────────
info "Enlazando configuraciones de aplicaciones..."

link_config "hypr"
link_config "waybar"
link_config "kitty"
link_config "rofi"
link_config "nvim"
link_config "kanata"
link_config "fastfetch"
link_config "mako/config"
link_config "swayosd"
link_config "avizo"
link_config "btop/btop.conf"
link_config "gh"

info "Enlazando archivos sueltos de ~/.config/..."
link_config "libinput-gestures.conf"
link_config "mimeapps.list"
link_config "user-dirs.dirs"
link_config "user-dirs.locale"

# ── Home files ───────────────────────────────────────────────
info "Enlazando archivos de home..."
link "$DOTFILES/linux/home/.bashrc" "$HOME/.bashrc"
link "$DOTFILES/linux/home/.gitconfig" "$HOME/.gitconfig"

# ── Scripts ──────────────────────────────────────────────────
info "Enlazando scripts de ~/.local/bin/..."
mkdir -p "$HOME/.local/bin"
for script in "$DOTFILES/linux/bin/"*; do
  name=$(basename "$script")
  link "$script" "$HOME/.local/bin/$name"
  chmod +x "$HOME/.local/bin/$name" 2>/dev/null || true
done

# ── XKB keyboard layout ─────────────────────────────────────
info "Instalando layout de teclado XKB..."
XKB_TARGET="/usr/share/X11/xkb/symbols/dvk_prog"
if [ -d "/usr/share/xkeyboard-config-2" ]; then
  XKB_TARGET="/usr/share/xkeyboard-config-2/symbols/dvk_prog"
fi
if [ -f "$XKB_TARGET" ] && [ ! -L "$XKB_TARGET" ]; then
  warn "XKB target existe como archivo real. Requiere sudo para reemplazar."
  echo "  Ejecutar manualmente:"
  echo "    sudo rm $XKB_TARGET"
  echo "    sudo ln -s $DOTFILES/linux/xkb/dvk_prog $XKB_TARGET"
elif [ -L "$XKB_TARGET" ]; then
  skip "XKB symlink ya existe"
else
  echo "  Para instalar layout XKB (requiere sudo):"
  echo "    sudo ln -s $DOTFILES/linux/xkb/dvk_prog $XKB_TARGET"
fi

echo ""
echo "════════════════════════════════════════"
echo "  Listo!"
if [ -d "$BACKUP_DIR" ]; then
  echo "  Backups en: $BACKUP_DIR"
fi
echo "  Recarga tu shell: exec bash"
echo "════════════════════════════════════════"
