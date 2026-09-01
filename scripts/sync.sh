#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$HOME/dotfiles"

info()  { echo -e "  [INFO]  $*"; }
ok()    { echo -e "  [OK]    $*"; }
warn()  { echo -e "  [WARN]  $*"; }
skip()  { echo -e "  [SKIP]  $*"; }

import_dir() {
  local src="$1"
  local dst="$2"
  local label="${3:-$src}"
  if [ -d "$src" ] && [ ! -L "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src/." "$dst/"
    ok "Importado $label -> $dst"
  elif [ -L "$src" ]; then
    skip "$label ya es symlink (gestionado por dotfiles)"
  else
    skip "$label no existe en origen"
  fi
}

import_file() {
  local src="$1"
  local dst="$2"
  local label="${3:-$src}"
  if [ -f "$src" ] && [ ! -L "$src" ]; then
    cp -a "$src" "$dst"
    ok "Importado $label -> $dst"
  elif [ -L "$src" ]; then
    skip "$label ya es symlink (gestionado por dotfiles)"
  else
    skip "$label no existe en origen"
  fi
}

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  dotfiles sync.sh                      ║"
echo "║  Importa configs existentes al repo    ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "  Importa archivos desde ~/.config/, ~/., etc."
echo "  hacia ~/dotfiles/ para ser gestionados."
echo "  NO sobrescribe archivos ya en el repo."
echo "  NO toca archivos que ya sean symlinks."
echo ""

# ── Config dirs ──────────────────────────────────────────────
info "Importando directorios de config..."
for dir in hypr waybar kitty nvim kanata fastfetch mako swayosd avizo btop gh; do
  import_dir "$HOME/.config/$dir" "$DOTFILES/linux/config/$dir" "~/.config/$dir"
done

# ── Config files ─────────────────────────────────────────────
info "Importando archivos sueltos de config..."
for f in libinput-gestures.conf mimeapps.list user-dirs.dirs user-dirs.locale; do
  import_file "$HOME/.config/$f" "$DOTFILES/linux/config/$f" "~/.config/$f"
done

# ── Home files ───────────────────────────────────────────────
info "Importando archivos de home..."
import_file "$HOME/.bashrc" "$DOTFILES/linux/home/.bashrc"
import_file "$HOME/.gitconfig" "$DOTFILES/linux/home/.gitconfig"

# ── Scripts ──────────────────────────────────────────────────
info "Importando scripts de ~/.local/bin/..."
mkdir -p "$DOTFILES/linux/bin"
for script in "$HOME/.local/bin/"*; do
  name=$(basename "$script")
  [ -f "$script" ] || continue
  import_file "$script" "$DOTFILES/linux/bin/$name" "~/.local/bin/$name"
done

# ── XKB ──────────────────────────────────────────────────────
info "Importando layout XKB..."
for target in /usr/share/xkeyboard-config-2/symbols/dvk_prog /usr/share/X11/xkb/symbols/dvk_prog; do
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    cp -a "$target" "$DOTFILES/linux/xkb/dvk_prog"
    ok "Importado $target"
    break
  fi
done

echo ""
echo "════════════════════════════════════════"
echo "  Listo! Revisa los cambios con:"
echo "    cd ~/dotfiles && git status"
echo "  Luego publica con:"
echo "    ~/dotfiles/scripts/publish.sh"
echo "════════════════════════════════════════"