#!/usr/bin/env bash
# ── setup-nixos.sh ──
# EL comando unico: clona el repo (si falta), genera hardware-config si es
# placeholder, hace nixos-rebuild switch, e instala Hermes.
#
# Uso (primer boot en NixOS):
#   bash ~/dotfiles/scripts/setup-nixos.sh
# o directamente desde cualquier sitio:
#   curl -fsSL https://raw.githubusercontent.com/estebaninfante/dotfiles/main/scripts/setup-nixos.sh | bash
set -euo pipefail

REPO_URL="https://github.com/estebaninfante/dotfiles.git"
DOTFILES="${DOTFILES:-$HOME/dotfiles}"
MACHINE="${MACHINE:-laptop}"   # override: MACHINE=desktop bash setup-nixos.sh

info() { echo -e "  [INFO]  $*"; }
ok()   { echo -e "  [OK]    $*"; }
warn() { echo -e "  [WARN]  $*"; }
error(){ echo -e "  [ERROR] $*"; }

echo ""
echo "╔════════════════════════════════════════╗"
echo "║  setup-nixos.sh                        ║"
echo "║  Un comando → todo configurado         ║"
echo "╚════════════════════════════════════════╝"
echo ""

# ── 0. ¿Estamos en NixOS? ──
if ! grep -q NixOS /etc/os-release 2>/dev/null; then
  error "Este script es para NixOS (estas en: $(. /etc/os-release; echo "$PRETTY_NAME"))"
  exit 1
fi

# ── 1. Clonar el repo si falta ──
if [ ! -d "$DOTFILES/.git" ]; then
  info "Clonando dotfiles en $DOTFILES..."
  git clone "$REPO_URL" "$DOTFILES"
else
  info "Repo ya existe en $DOTFILES"
  git -C "$DOTFILES" pull --ff-only || warn "pull fallo (continuando con lo local)"
fi

cd "$DOTFILES"

# ── 2. Hardware-config: si es placeholder, generarlo ──
HW_FILE="nixos/hosts/hardware-configuration.$MACHINE.nix"
if grep -q "NO USAR TAL CUAL\|no se genera por maquina" "$HW_FILE" 2>/dev/null \
   || ! grep -q "fileSystems" "$HW_FILE" 2>/dev/null; then
  info "Generando hardware-configuration real (placeholder detectado)..."
  TMP_DIR=$(mktemp -d)
  sudo nixos-generate-config --root / --dir "$TMP_DIR" >/dev/null 2>&1 \
    || sudo nixos-generate-config --root / -d "$TMP_DIR" >/dev/null 2>&1
  if [ -f "$TMP_DIR/hardware-configuration.nix" ]; then
    sudo cp "$TMP_DIR/hardware-configuration.nix" "$HW_FILE"
    sudo chown "$USER" "$HW_FILE"
    ok "hardware-configuration generado → $HW_FILE"
  else
    warn "No se pudo generar hardware-config; usando placeholder (riesgo)"
  fi
  rm -rf "$TMP_DIR"
else
  ok "hardware-configuration ya presente"
fi

# ── 3. nixos-rebuild switch (TODO el sistema + paquetes + configs) ──
info "Aplicando config NixOS (paquetes, servicios, dotfiles)..."
sudo nixos-rebuild switch --flake "$DOTFILES#$MACHINE" 2>&1 | tail -5 || {
  error "nixos-rebuild fallo. Revisa el error arriba y vuelve a ejecutar este script."
  exit 1
}
ok "Sistema reconstruido"

# ── 4. opencode: symlink a ~/.opencode/bin (F8 de hyprland.lua lo usa) ──
if command -v opencode &>/dev/null; then
  mkdir -p "$HOME/.opencode/bin"
  ln -sf "$(command -v opencode)" "$HOME/.opencode/bin/opencode"
  ok "opencode disponible (y en ~/.opencode/bin)"
else
  warn "opencode no encontrado — revisa nixos/modules/packages.nix"
fi

# ── 5. Hermes (no esta en nixpkgs → instalador oficial) ──
if command -v hermes &>/dev/null || [ -x "$HOME/.hermes/bin/hermes" ]; then
  ok "Hermes ya instalado"
else
  info "Instalando Hermes Agent..."
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash || {
    warn "Instalacion de Hermes fallo — ejecuta manualmente:"
    warn "  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
  }
  ok "Hermes instalado"
fi

# ── 6. Verificacion final ──
echo ""
echo "════════════════════════════════════════"
echo "  Verificacion final:"
for cmd in nvim opencode handy kitty hyprland; do
  if command -v "$cmd" &>/dev/null; then
    ok "$cmd: $(command -v "$cmd")"
  else
    warn "$cmd: NO encontrado"
  fi
done
if command -v hermes &>/dev/null || [ -x "$HOME/.hermes/bin/hermes" ]; then
  ok "hermes: instalado"
else
  warn "hermes: NO encontrado"
fi
echo ""
echo "  Siguiente paso:"
echo "    exec bash   # recargar shell"
echo "    hermes setup  # configurar provider/modelo (una vez)"
echo "════════════════════════════════════════"
