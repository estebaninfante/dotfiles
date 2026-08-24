#!/usr/bin/env bash
# ── rebuild.sh ──
# Wrapper SEGURO de nixos-rebuild: detecta la maquina por HARDWARE,
# valida hardware-configuration contra el root UUID real y SOLO
# entonces ejecuta nixos-rebuild con el host correcto.
#
# Motivo: un rebuild con host equivocado (#laptop en desktop o viceversa)
# genera una generacion con hardware-configuration de OTRA maquina ->
# boot roto / emergency mode. Este script lo hace imposible.
#
# Uso:
#   bash ~/dotfiles/scripts/rebuild.sh            # switch (default)
#   bash ~/dotfiles/scripts/rebuild.sh boot       # boot|test|build|dry-build...
#
# NUNCA llamar a 'sudo nixos-rebuild --flake ~/dotfiles#laptop|#desktop'
# directamente: usar SIEMPRE este script.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${1:-switch}"

case "$ACTION" in
  switch|boot|test|build|dry-build|dry-activate|edit) ;;
  *)
    echo "ERROR: accion desconocida '$ACTION'" >&2
    echo "Uso: rebuild.sh [switch|boot|test|build|dry-build|dry-activate|edit]" >&2
    exit 1
    ;;
esac
shift || true

# ── 1. Deteccion por HARDWARE real (DMI/bateria/backlight) ──
# Igual que setup-nixos.sh: no confiar en archivos ni defaults.
machine="$(bash "$REPO/scripts/detect-machine.sh")"

# ── 2. Validar hardware-configuration.$machine.nix contra root UUID real ──
root_uuid="$(findmnt -no UUID /)"
conf_uuid="$(grep -m1 -oE 'by-uuid/[A-Za-z0-9-]+' \
  "$REPO/nixos/hosts/hardware-configuration.$machine.nix" | awk -F/ '{print $NF}')"

if [ -z "$conf_uuid" ]; then
  echo "ABORTADO: no pude leer UUID de hardware-configuration.$machine.nix" >&2
  exit 1
fi

if [ "$root_uuid" != "$conf_uuid" ]; then
  echo "" >&2
  echo "ABORTADO: hardware-configuration.$machine.nix apunta al UUID $conf_uuid" >&2
  echo "pero el root REAL de esta maquina es $root_uuid." >&2
  echo "El repo contiene hardware de otra maquina; un rebuild romperia el boot." >&2
  echo "" >&2
  echo "(Si estas en un fresh install usa scripts/setup-nixos.sh, que regenera" >&2
  echo " el hardware-configuration automaticamente.)" >&2
  exit 1
fi

# ── 3. Aviso si ~/.config/machine-type discrepa (la deteccion gana) ──
if [ -f "$HOME/.config/machine-type" ] && \
   [ "$(tr -d '[:space:]' <"$HOME/.config/machine-type")" != "$machine" ]; then
  echo "AVISO: machine-type dice otra cosa; gana la deteccion por hardware: '$machine'" >&2
fi

echo "→ sudo nixos-rebuild $ACTION --flake $REPO#$machine"
exec sudo nixos-rebuild "$ACTION" --flake "$REPO#$machine" "$@"
