#!/usr/bin/env bash
# Sync unidireccional laptop -> desktop (NixOS).
# Fuente de verdad: ~/developing de la laptop.
# Requiere: tailscale (MagicDNS resuelve "desktop"), llave SSH autorizada,
# y openssh habilitado en el desktop (nixos/configuration.nix).
set -euo pipefail

DEST="desktop:~/developing/"

info() { echo "  [INFO]  $*"; }
ok()   { echo "  [OK]    $*"; }

info "Sincronizando ~/developing -> $DEST"
rsync -az --delete --itemize-changes "$HOME/developing/" "$DEST"
ok "Sync completado"
