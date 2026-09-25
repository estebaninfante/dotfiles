#!/usr/bin/env bash
# Rebuild + install the local hyprexpo fork with the local patch.
#
# The patch (linux/patches/hyprexpo-local.patch) bundles:
#   - "instant retarget": close() re-targets the running animation and
#     kb_selectn works while closing, so a rapid SUPER+<n> redirects mid-flight.
#   - the experimental 3D grid (Overview3D.*: perspective-warped tiles behind
#     plugin:hyprexpo:threed_enable, default off).
#   - scripts/verify-3d.sh + the nested dev scaffolding.
#
# This rebuilds from the pinned upstream commit + the local patch and installs
# into the hyprpm cache the config loads from. Re-run after `hyprpm update`
# (which would otherwise overwrite the .so with a stock build).
set -euo pipefail

PIN=5891014c611e1bd56d0121143f0221d46b5c0967
REPO=https://github.com/sandwichfarm/hyprexpo

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PATCH="$HERE/../patches/hyprexpo-local.patch"
SRC="${HYPREXPO_SRC:-$HOME/.cache/hyprexpo-src}"

INSTALL_USER="${SUDO_USER:-$USER}"
INSTALL_DIR="/var/cache/hyprpm/$INSTALL_USER/hyprexpo"
INSTALL_SO="$INSTALL_DIR/hyprexpo.so"

[ -f "$PATCH" ] || { echo "error: patch not found: $PATCH" >&2; exit 1; }

if [ ! -d "$SRC/.git" ]; then
    git clone "$REPO" "$SRC"
fi

git -C "$SRC" fetch --all --tags --quiet
git -C "$SRC" checkout --quiet "$PIN"
git -C "$SRC" reset --hard --quiet "$PIN"
git -C "$SRC" clean -fdq
git -C "$SRC" apply "$PATCH"

make -C "$SRC" -j"$(nproc)"

sudo install -Dm755 "$SRC/hyprexpo.so" "$INSTALL_SO"

# NUNCA hacer `hyprctl plugin unload/load` en la sesion viva: descargar un
# plugin que registra pass elements/hooks tumba Hyprland (crash -> safe-mode,
# se pierden las apps). El .so nuevo se aplica al reiniciar Hyprland; para
# probar sin reiniciar usar el harness anidado (hyprexpo-verify-3d.sh).
echo "installed: $INSTALL_SO (aplica en el proximo arranque de Hyprland)"
