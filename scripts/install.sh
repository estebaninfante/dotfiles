#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$HOME/dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
FORCE=false
DRY_RUN=false
PACKAGES=false

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --dry-run) DRY_RUN=true ;;
    --packages) PACKAGES=true ;;
  esac
done

# ── Si se pide --packages, instalar paquetes primero ──
if [ "$PACKAGES" = true ]; then
  SETUP_SCRIPT="$DOTFILES/scripts/setup-packages.sh"
  if [ -f "$SETUP_SCRIPT" ]; then
    echo "  Ejecutando setup-packages.sh..."
    bash "$SETUP_SCRIPT" ${DRY_RUN:+--dry-run}
    echo ""
  else
    echo "  [WARN] setup-packages.sh no encontrado en $SETUP_SCRIPT"
  fi
fi

info()  { echo -e "  [INFO]  $*"; }
ok()    { echo -e "  [OK]    $*"; }
warn()  { echo -e "  [WARN]  $*"; }
skip()  { echo -e "  [SKIP]  $*"; }
error() { echo -e "  [ERROR] $*"; }

ERRORS=0

backup() {
  local target="$1"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    mkdir -p "$BACKUP_DIR"
    mv "$target" "$BACKUP_DIR/"
    warn "Backup: $target -> $BACKUP_DIR/"
  fi
}

link() {
  local src="$1"
  local dst="$2"

  if [ ! -e "$src" ]; then
    error "Origen no existe: $src"
    ERRORS=$((ERRORS + 1))
    return
  fi

  if [ -L "$dst" ]; then
    local current
    current=$(readlink "$dst")
    if [ "$current" = "$src" ]; then
      skip "$dst -> $src (ya existe)"
      return
    fi
    warn "Symlink diferente: $dst -> $current (esperado: $src)"
    [ "$DRY_RUN" = false ] && rm -f "$dst"
  elif [ -e "$dst" ]; then
    if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
      local ans
      read -r -p "  $dst ya existe. Sobrescribir? [y/N] " ans
      if [[ ! "$ans" =~ ^[Yy]$ ]]; then
        skip "$dst (omitido por usuario)"
        return
      fi
    fi
    [ "$DRY_RUN" = false ] && backup "$dst"
    [ "$DRY_RUN" = false ] && rm -rf "$dst"
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] ln -s $src $dst"
    return
  fi

  ln -s "$src" "$dst"

  if [ ! -L "$dst" ] || [ "$(readlink -f "$dst")" != "$(readlink -f "$src")" ]; then
    error "Symlink invalido: $dst -> $src"
    ERRORS=$((ERRORS + 1))
    return
  fi

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
  gdm/black.png
)

HOME_FILES=(
  .bashrc
  .gitconfig
)

SYSTEM_FILES_XKB=(
  "linux/xkb/dvk_prog:/usr/share/xkeyboard-config-2/symbols/dvk_prog"
  "linux/xkb/dvk_prog:/usr/share/X11/xkb/symbols/dvk_prog"
)

# ── Helpers ──────────────────────────────────────────────────

entry_status() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "linked"
  elif [ -e "$dst" ]; then
    echo "replace"
  else
    echo "create"
  fi
}

check_source() {
  local src="$1"
  if [ ! -e "$src" ]; then
    error "Origen no existe: $src"
    ERRORS=$((ERRORS + 1))
    return 1
  fi
}

validate_symlink() {
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
    echo "  ✓ $dst"
    return 0
  else
    echo "  ✗ $dst"
    ERRORS=$((ERRORS + 1))
    return 1
  fi
}

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  dotfiles install.sh                   ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ── Summary phase ───────────────────────────────────────────

LINKED=0
REPLACE=0
CREATE=0

summary_entries=()

for dir in "${CONFIG_DIRS[@]}"; do
  summary_entries+=("$DOTFILES/linux/config/$dir:$HOME/.config/$dir")
done

for file in "${CONFIG_FILES[@]}"; do
  summary_entries+=("$DOTFILES/linux/config/$file:$HOME/.config/$file")
done

for file in "${HOME_FILES[@]}"; do
  summary_entries+=("$DOTFILES/linux/home/$file:$HOME/$file")
done

for script in "$DOTFILES/linux/bin/"*; do
  [ -f "$script" ] || continue
  name=$(basename "$script")
  summary_entries+=("$script:$HOME/.local/bin/$name")
done

for entry in "${summary_entries[@]}"; do
  src="${entry%%:*}"
  dst="${entry##*:}"
  check_source "$src" || continue
  status=$(entry_status "$src" "$dst")
  case "$status" in
    linked) LINKED=$((LINKED + 1)) ;;
    replace) REPLACE=$((REPLACE + 1)) ;;
    create) CREATE=$((CREATE + 1)) ;;
  esac
done

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  error "Errores en la comprobacion de origenes. Abortando."
  exit 1
fi

echo "  Resumen de acciones:"
echo "    Ya enlazados:    $LINKED"
echo "    Se reemplazaran: $REPLACE"
echo "    Se crearan:      $CREATE"
if [ "$DRY_RUN" = true ]; then
  echo "    (modo --dry-run: no se modificara nada)"
fi
echo ""

if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
  read -r -p "  Continuar? [y/N] " ans
  if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "  Abortado por el usuario."
    exit 0
  fi
  echo ""
fi

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
  [ "$DRY_RUN" = false ] && chmod +x "$HOME/.local/bin/$name" 2>/dev/null || true
done

# ── System files (XKB) ──────────────────────────────────────
info "Instalando layout de teclado XKB..."
for entry in "${SYSTEM_FILES_XKB[@]}"; do
  src_rel="${entry%%:*}"
  target="${entry##*:}"
  src="$DOTFILES/$src_rel"
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    warn "$target existe como archivo real. Requiere sudo para reemplazar."
    echo "    sudo rm $target"
    echo "    sudo ln -s $src $target"
  elif [ -L "$target" ]; then
    skip "XKB symlink ya existe en $target"
  else
    echo "    Para instalar layout XKB (requiere sudo):"
    echo "    sudo ln -s $src $target"
  fi
done

# ── Validation ───────────────────────────────────────────────
echo ""
info "Validando symlinks..."

for dir in "${CONFIG_DIRS[@]}"; do
  validate_symlink "$DOTFILES/linux/config/$dir" "$HOME/.config/$dir"
done

for file in "${CONFIG_FILES[@]}"; do
  validate_symlink "$DOTFILES/linux/config/$file" "$HOME/.config/$file"
done

for file in "${HOME_FILES[@]}"; do
  validate_symlink "$DOTFILES/linux/home/$file" "$HOME/$file"
done

for script in "$DOTFILES/linux/bin/"*; do
  [ -f "$script" ] || continue
  name=$(basename "$script")
  validate_symlink "$script" "$HOME/.local/bin/$name"
done

# ── Final ────────────────────────────────────────────────────
echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "  Se encontraron $ERRORS errores."
  exit 1
fi

echo "════════════════════════════════════════"
echo "  Listo!"
if [ -d "$BACKUP_DIR" ]; then
  echo "  Backups en: $BACKUP_DIR"
fi
echo "  Recarga tu shell: exec bash"
echo "════════════════════════════════════════"