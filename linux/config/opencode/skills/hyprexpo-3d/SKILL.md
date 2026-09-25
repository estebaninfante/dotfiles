---
name: hyprexpo-3d
description: Verify and iterate the local hyprexpo 3D grid (perspective-warped workspace overview) built on the sandwichfarm/hyprexpo fork. Use when checking that the 3D render works, tuning tilt/yaw/distance, or debugging the plugin — runs a safe nested Hyprland, never the live session. Triggers: hyprexpo 3D, grilla 3D, verify-3d, threed_enable, overview perspective.
---

# hyprexpo 3D grid — verify & iterate

Local fork of `sandwichfarm/hyprexpo` (pinned `e95ef2e`) patched with
`~/dotfiles/linux/patches/hyprexpo-local.patch`. The patch adds:

- **instant retarget**: `close()` re-targets the in-flight animation, `kb_selectn`
  works while closing → rapid `SUPER+<n>` redirects mid-flight.
- **experimental 3D grid** (`Overview3D.cpp/.hpp`): perspective-warped tiles from
  a nested custom GLSL shader (vertex outputs `w = depth`, the native shader
  forces `w = 1` and can't do perspective). Gated behind
  `plugin:hyprexpo:threed_enable` (**default 0 = off**, live session safe).

## Verify (one command)

```bash
HYPREXPO_DEV_3D_TILT=55 ~/dotfiles/linux/bin/hyprexpo-verify-3d.sh
# → prints SUMMARY + PNG path, e.g. /tmp/opencode/hyprexpo-3d/overview3d.png
```

Then **look at the PNG** (Read tool renders it). Warped tiles = receding/tilted
like a floor. Flat axis-aligned tiles = 3D not applied.

Env knobs: `HYPREXPO_DEV_3D_TILT/_YAW/_DIST/_RADIUS/_FLIPV`,
`HYPREXPO_VERIFY_OUT`, `HYPREXPO_DEV_MODE` (default `900x600@60`),
`HYPREXPO_VERIFY_SETTLE_MS`.

## Rebuild after edits

Edited the plugin clone (`${HYPREXPO_SRC:-~/.cache/hyprexpo-src}`)? The verify
script re-applies pin+patch from a clean tree, so to test **local uncommitted
edits** build in the clone directly first (a full build is ~60s; the verifier's
IPC wait is ~20s, so prebuild or the first run fails `no-nested-ipc`):

```bash
cd "${HYPREXPO_SRC:-$HOME/.cache/hyprexpo-src}" && make dev-build   # → ~/.cache/hyprexpo/hyprexpo.so
```

To install the patched plugin into the live session (after `hyprpm update`
would overwrite it): `~/dotfiles/linux/bin/hyprexpo-rebuild.sh`.

> **NEVER `hyprctl plugin unload/load` on the live session.** Unloading a plugin
> that registered pass elements/hooks **crashes Hyprland** → watchdog relaunches
> in `--safe-mode` (no autostart, apps lost). The rebuild script only *installs*
> the `.so`; it applies on the next Hyprland start. To test without restarting,
> use the nested verifier above.

> **NEVER** run `hyprctl plugin unload/load` on the live session. Unloading a
> plugin that registered pass elements / hooks **crashes Hyprland** (watchdog
> restarts it in `--safe-mode` with no autostart → user loses the session).
> `hyprctl reload` does **not** reload the `.so` either. The rebuilt plugin only
> takes effect on the **next Hyprland start** (logout/login). To test now, use
> the nested verifier instead.

## Nested harness facts (in scripts/verify-3d.sh)

- Nested compositor = host window with class `aquamarine` (title `aquamarine - WAYLAND-1`).
- Nested IPC: pick the newest dir in `$XDG_RUNTIME_DIR/hypr/` that is != the host
  sig and answers `hyprctl -j version`; drive it with
  `HYPRLAND_INSTANCE_SIGNATURE=<sig> hyprctl ...`.
- Open overview: `HYPRLAND_INSTANCE_SIGNATURE=<sig> hyprctl dispatch hyprexpo:expo toggle`.
- Capture: `grim -g "<x>,<y> <w>x<h>" out.png` on the host window region.
- **Launching gotcha**: background the nested via `setsid ... </dev/null >log 2>&1 &`
  from inside a script, else the tool call hangs on the process group.

### Log visibility trap

Nested stdout shows only `WARN`/`ERR` (INFO is suppressed). A success log at INFO
is invisible → `shader_ready=no` in the SUMMARY is a **false negative**. Judge the
3D from the PNG, not the log. `ERR ]: Invalid dispatcher: hyprexpo:*` at startup
is benign (config parses before the plugin registers).

## Config values (server-side, `plugin:hyprexpo:`)

`threed_enable` (0/1), `threed_tilt` (deg), `threed_yaw` (deg), `threed_distance`
(×monitor height), `threed_radius` (UV 0..0.5), `threed_flip_v` (0/1).

## Known follow-ups

- Focus/hover **borders** and **labels** are still drawn axis-aligned (native
  `renderBorder`/`renderTexture` over the flat box); they don't yet follow the
  warped tile. Warping them is the next step for a coherent 3D look.
- 3D is grid-only; `CScrollingOverview` is a separate layout.
