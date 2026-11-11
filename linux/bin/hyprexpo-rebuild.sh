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
git -C "$SRC" checkout -f --quiet "$PIN"
git -C "$SRC" reset --hard --quiet "$PIN"
git -C "$SRC" clean -fdq
git -C "$SRC" apply "$PATCH"

# Guard anti-regresion: los previews en vivo de tiles en otros workspaces
# dependen de COverview::startLiveRefresh (timer 33ms que recaptura tiles
# ocultos; sin ella las terminales en otros espacios quedan congeladas en la
# captura de apertura — regresion del rebase 77a961d). Si el patch llego a
# perder ese hunk, fallar en vez de instalar un build roto.
if ! grep -q "startLiveRefresh" "$SRC/OverviewInteraction.cpp"; then
    echo "error: el patch perdio startLiveRefresh (preview en vivo de tiles ocultos)" >&2
    echo "       ver linux/config/hypr/hyprexpo-changes.md" >&2
    exit 1
fi

if ! grep -q "hoverSelectParked" "$SRC/OverviewInteraction.cpp" || ! grep -q "armHoverSelectPark" "$SRC/Overview.cpp"; then
    echo "error: el patch perdio el park timer de hover-select (seleccion al abrir por la esquina)" >&2
    echo "       ver linux/config/hypr/hyprexpo-changes.md" >&2
    exit 1
fi

# El repintado del fondo real ahora vive en OverviewRender.cpp (antes en main.cpp,
# donde quedaba DESPUES de los tiles y los tapaba).
if ! grep -q "background_transparent" "$SRC/PluginConfig.cpp" || ! grep -q "backgroundTransparent" "$SRC/OverviewRender.cpp"; then
    echo "error: el patch perdio background_transparent (fondo transparente para video de linux-wallpaperengine)" >&2
    echo "       ver linux/config/hypr/hyprexpo-changes.md" >&2
    exit 1
fi

if ! grep -q "keep_layers" "$SRC/PluginConfig.cpp" || ! grep -q "keep_layers" "$SRC/main.cpp" || ! grep -q "ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY" "$SRC/main.cpp"; then
    echo "error: el patch perdio keep_layers (barra y overlays de voz visibles sobre el overview)" >&2
    echo "       ver linux/config/hypr/hyprexpo-changes.md" >&2
    exit 1
fi

# Guards anti-regresion de orientacion. El overview 3D tiene que proyectarse desde
# el pixel-space del monitor (m_pixelSize, el buffer sin rotar) con el transform de
# salida: ese es el unico par que cubre la pantalla entera con la rotacion incluida.
# Con m_transformedSize (el tamano ya rotado) los ejes se entrecruzan y la grilla
# queda anisotropica y fuera de cuadro; sin transform queda entera pero girada 90.
# Ademas la captura de los previews tiene que salir en el espacio ya rotado del
# monitor (transformedSize), sin el flip de 180 que solo servia para 180 grados.
# Ver "2026-11-10 - overview 3D en pantalla girada" en el changes.
if ! grep -q "outputProjection(MON->m_pixelSize, Math::wlTransformToHyprutils(MON->m_transform))" "$SRC/OverviewRender.cpp"; then
    echo "error: la projection 3D tiene que ser pixel-space (m_pixelSize) + transform de salida" >&2
    echo "       ver linux/config/hypr/hyprexpo-changes.md" >&2
    exit 1
fi

if grep -q "outputProjection(MON->m_transformedSize" "$SRC/OverviewRender.cpp"; then
    echo "error: la projection 3D volvio a usar el tamano rotado en vez del buffer (grilla anisotropica en vertical)" >&2
    echo "       ver linux/config/hypr/hyprexpo-changes.md" >&2
    exit 1
fi

# Captura de previews en monitor rotado: NO se toca el estado del monitor (mismo
# transform, escala y tamanos que en vivo). Ajustarlos hacia que los marcos de
# ventana y las superficies se dibujaran a escalas distintas (contenido recortado o
# al 80%). La textura se marca con la rotacion INVERSA para que el tile la muestre
# derecha: si eso desaparece, los previews salen girados 90/180.
if ! grep -q "inverseTransformOf" "$SRC/OverviewCapture.cpp" || grep -q "monitorState.transformedSize()" "$SRC/OverviewCapture.cpp"; then
    echo "error: la captura de previews volvio a manipular el estado del monitor o perdio la rotacion inversa" >&2
    echo "       ver linux/config/hypr/hyprexpo-changes.md" >&2
    exit 1
fi

if ! grep -q "makeEGLCurrent" "$SRC/Overview3D.cpp" || ! grep -q "HYPREXPO_DEV_TRANSFORM" "$SRC/scripts/run-nested.sh"; then
    echo "error: el patch perdio el EGL current del init 3D o la rotacion del harness nested" >&2
    echo "       ver linux/config/hypr/hyprexpo-changes.md" >&2
    exit 1
fi

make -C "$SRC" -j"$(nproc)"

sudo install -Dm755 "$SRC/hyprexpo.so" "$INSTALL_SO"

# NUNCA hacer `hyprctl plugin unload/load` en la sesion viva: descargar un
# plugin que registra pass elements/hooks tumba Hyprland (crash -> safe-mode,
# se pierden las apps). El .so nuevo se aplica al reiniciar Hyprland; para
# probar sin reiniciar usar el harness anidado (hyprexpo-verify-3d.sh).
echo "installed: $INSTALL_SO (aplica en el proximo arranque de Hyprland)"
