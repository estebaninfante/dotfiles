#!/usr/bin/env bash
# Rebuild + install the local hyprexpo fork with the "instant retarget" patch.
#
# Why: the stock plugin ignores workspace changes while its close morph is in
# flight, so a rapid SUPER+<n> gets dropped (or queued) and the 3D zoom can't be
# re-aimed mid-flight. The patch (linux/patches/hyprexpo-retarget.patch) makes
# close() re-target the running animation and lets kb_selectn act during closing.
#
# This rebuilds from the pinned upstream commit + the local patch and installs
# into the hyprpm cache the config loads from. Re-run after `hyprpm update`
# (which would otherwise overwrite the .so with a stock build).
set -euo pipefail

PIN=e95ef2e686fccda8e777727a8c41b8747bf18794
REPO=https://github.com/sandwichfarm/hyprexpo

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PATCH="$HERE/../patches/hyprexpo-retarget.patch"
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
git -C "$SRC" clean -fdq
git -C "$SRC" apply "$PATCH"

make -C "$SRC" -j"$(nproc)"

sudo install -Dm755 "$SRC/hyprexpo.so" "$INSTALL_SO"

hyprctl plugin unload "$INSTALL_SO" >/dev/null 2>&1 || true
hyprctl plugin load "$INSTALL_SO"
hyprctl plugin list
