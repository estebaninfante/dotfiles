#!/usr/bin/env bash
# hyprexpo-verify-3d.sh — automated visual check of the local hyprexpo 3D grid.
#
# Ensures the local plugin source (pinned upstream + local patch) exists, then
# runs its nested-Hyprland verifier: it launches a throwaway nested compositor
# (NEVER the live session), opens the overview, screenshots the nested window and
# prints a compact SUMMARY + the PNG path. Look at the PNG to judge the 3D.
#
# The live config is untouched: 3D is gated behind plugin:hyprexpo:threed_enable
# (default 0). Everything here runs in a nested window.
#
# Env knobs (passed through to scripts/verify-3d.sh):
#   HYPREXPO_DEV_MODE       nested output mode      (default 900x600@60)
#   HYPREXPO_DEV_3D         0/1 enable 3D            (default 1)
#   HYPREXPO_DEV_3D_TILT / _YAW / _DIST / _RADIUS / _FLIPV  warp params
#   HYPREXPO_VERIFY_OUT     output dir               (default /tmp/opencode/hyprexpo-3d)
#   HYPREXPO_VERIFY_SETTLE_MS  settle before capture (default 1400)
set -euo pipefail

PIN=e95ef2e686fccda8e777727a8c41b8747bf18794
REPO=https://github.com/sandwichfarm/hyprexpo

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PATCH="$HERE/../patches/hyprexpo-local.patch"
SRC="${HYPREXPO_SRC:-$HOME/.cache/hyprexpo-src}"

[ -f "$PATCH" ] || { echo "error: patch not found: $PATCH" >&2; exit 1; }

if [ ! -d "$SRC/.git" ]; then
    git clone "$REPO" "$SRC"
fi

git -C "$SRC" fetch --all --tags --quiet
git -C "$SRC" checkout --quiet "$PIN"
git -C "$SRC" reset --hard --quiet "$PIN"
git -C "$SRC" clean -fdq
git -C "$SRC" apply "$PATCH"

exec "$SRC/scripts/verify-3d.sh"
