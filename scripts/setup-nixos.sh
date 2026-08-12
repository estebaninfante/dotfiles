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

# ── Machine type ──
# Auto-detectado por HARDWARE (DMI/bateria/backlight) via detect-machine.sh
# (del repo ya clonado). Override explicito: MACHINE=desktop bash setup-nixos.sh
# ⚠️ NO asumir "laptop" por defecto: fue el bug que instalo el desktop como
# laptop y contamino hardware-configuration.laptop.nix con hardware real.
# Si la deteccion falla, preguntar en vez de asumir.
if [ -z "${MACHINE:-}" ]; then
  MACHINE="$(bash scripts/detect-machine.sh 2>/dev/null || true)"
  if [ "$MACHINE" != "laptop" ] && [ "$MACHINE" != "desktop" ]; then
    warn "No se pudo detectar la maquina por hardware"
    read -r -p "  ¿Que maquina es esta? [laptop/desktop]: " MACHINE
  else
    info "Maquina detectada por hardware: $MACHINE"
  fi
fi
if [ "$MACHINE" != "laptop" ] && [ "$MACHINE" != "desktop" ]; then
  error "MACHINE invalido: '$MACHINE' (debe ser 'laptop' o 'desktop')"
  exit 1
fi

# ── 2. Hardware-config: si es placeholder, tomar el del sistema ──
# En un NixOS ya instalado, /etc/nixos/hardware-configuration.nix YA existe
# (lo genera el instalador con el hardware real). Se copia directamente.
# Solo si NO existe se regenera con nixos-generate-config (fallback).
#
# ⚠️ Validacion de pertenencia: el archivo del repo puede tener hardware de
# OTRA maquina (p.ej. desktop contaminando hardware-configuration.laptop.nix).
# Se compara el UUID del root montado actual contra el del archivo; si no
# coincide, se regenera. Sin esto, un fresh install usaria particiones ajenas.
HW_FILE="nixos/hosts/hardware-configuration.$MACHINE.nix"
ROOT_UUID="$(findmnt -no UUID / 2>/dev/null | tr -d '[:space:]' || true)"
needs_regenerate=false
if ! grep -q "fileSystems" "$HW_FILE" 2>/dev/null; then
  needs_regenerate=true
elif [ -n "$ROOT_UUID" ] && ! grep -q "$ROOT_UUID" "$HW_FILE"; then
  warn "hardware-configuration.$MACHINE.nix no coincide con esta maquina (root UUID $ROOT_UUID)"
  warn "→ regenerando para evitar montar particiones de otra maquina"
  needs_regenerate=true
fi

if [ "$needs_regenerate" = true ]; then
  if [ -f /etc/nixos/hardware-configuration.nix ]; then
    info "Copiando /etc/nixos/hardware-configuration.nix (ya generado por el instalador)..."
    cp /etc/nixos/hardware-configuration.nix "$HW_FILE"
    chown "$USER" "$HW_FILE" 2>/dev/null || true
    ok "hardware-configuration copiado → $HW_FILE"
  else
    info "Regenerando hardware-configuration con nixos-generate-config..."
    TMP_DIR=$(mktemp -d)
    if ! sudo nixos-generate-config --root / --dir "$TMP_DIR" 2>&1 \
         && ! sudo nixos-generate-config --root / -d "$TMP_DIR" 2>&1; then
      warn "No se pudo generar hardware-config; usando placeholder (riesgo)"
    else
      [ -f "$TMP_DIR/hardware-configuration.nix" ] && cp "$TMP_DIR/hardware-configuration.nix" "$HW_FILE"
      ok "hardware-configuration generado → $HW_FILE"
    fi
    rm -rf "$TMP_DIR"
  fi
else
  ok "hardware-configuration ya presente y coincide con esta maquina"
fi

# ── 3. nixos-rebuild switch (TODO el sistema + paquetes + configs) ──
info "Aplicando config NixOS (paquetes, servicios, dotfiles)..."
info "Primera vez tarda 10-20 min (descarga ~295 paquetes)."
info "La salida se muestra en vivo — si ves 'building' o 'downloading' esta funcionando."
echo ""
sudo nixos-rebuild switch --flake "$DOTFILES#$MACHINE" || {
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
