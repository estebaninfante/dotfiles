#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$HOME/dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
FORCE=false

[ "${1:-}" = "--force" ] && FORCE=true

info()  { echo -e "  [INFO]  $*"; }
ok()    { echo -e "  [OK]    $*"; }
warn()  { echo -e "  [WARN]  $*"; }
skip()  { echo -e "  [SKIP]  $*"; }

backup() {
  local target="$1"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    mkdir -p "$BACKUP_DIR"
    cp -a "$target" "$BACKUP_DIR/"
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
    fi
    warn "Symlink diferente: $dst -> $current (esperado: $src)"
    rm -f "$dst"
  elif [ -e "$dst" ]; then
    if [ "$FORCE" = false ]; then
      local ans
      read -r -p "  $dst ya existe. Sobrescribir? [y/N] " ans
      if [[ ! "$ans" =~ ^[Yy]$ ]]; then
        skip "$dst (omitido por usuario)"
        return
      fi
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

link_home() {
  link "$DOTFILES/linux/home/$1" "$HOME/$1"
}

# ── Inventories ─────────────────────────────────────────────
# Add new entries here — only one line needed per config.
# Format: relative path under linux/config/

CONFIG_DIRS=(
  hypr
  waybar
  kitty
  rofi
  nvim
  kanata
  fastfetch
  mako
  swayosd
  avizo
  btop
  gh
)

CONFIG_FILES=(
  libinput-gestures.conf
  mimeapps.list
  user-dirs.dirs
  user-dirs.locale
)

HOME_FILES=(
  .bashrc
  .gitconfig
)

SYSTEM_FILES_XKB=(
  "linux/xkb/dvk_prog:/usr/share/xkeyboard-config-2/symbols/dvk_prog"
  "linux/xkb/dvk_prog:/usr/share/X11/xkb/symbols/dvk_prog"
)

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  dotfiles install.sh                   ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ── Config directories ──────────────────────────────────────
info "Enlazando directorios de configuracion..."
for dir in "${CONFIG_DIRS[@]}"; do
  link_config "$dir"
done

# ── Config files ────────────────────────────────────────────
info "Enlazando archivos sueltos de configuracion..."
for file in "${CONFIG_FILES[@]}"; do
  link_config "$file"
done

# ── Home files ───────────────────────────────────────────────
info "Enlazando archivos de home..."
for file in "${HOME_FILES[@]}"; do
  link_home "$file"
done

# ── Scripts ──────────────────────────────────────────────────
info "Enlazando scripts de ~/.local/bin/..."
mkdir -p "$HOME/.local/bin"
for script in "$DOTFILES/linux/bin/"*; do
  [ -f "$script" ] || continue
  name=$(basename "$script")
  link "$script" "$HOME/.local/bin/$name"
  chmod +x "$HOME/.local/bin/$name" 2>/dev/null || true
done

# ── System files (XKB) ──────────────────────────────────────
info "Instalando layout de teclado XKB..."
for entry in "${SYSTEM_FILES_XKB[@]}"; do
  src_rel="${entry%%:*}"
  target="${entry##*:}"
  src="$DOTFILES/$src_rel"
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    warn "$target existe como archivo real. Requiere sudo para reemplazar."
    echo "  Ejecutar manualmente:"
    echo "    sudo rm $target"
    echo "    sudo ln -s $src $target"
  elif [ -L "$target" ]; then
    skip "XKB symlink ya existe en $target"
  else
    echo "  Para instalar layout XKB (requiere sudo):"
    echo "    sudo ln -s $src $target"
  fi
done

echo ""
echo "════════════════════════════════════════"
echo "  Listo!"
if [ -d "$BACKUP_DIR" ]; then
  echo "  Backups en: $BACKUP_DIR"
fi
echo "  Recarga tu shell: exec bash"
echo "════════════════════════════════════════"