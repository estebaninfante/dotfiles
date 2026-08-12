#!/usr/bin/env bash
# build-lan-mouse-patched.sh
# Compila lan-mouse desde fuente con el patch de AltGr (Mod5).
# Ejecutar en la máquina Fedora (la que usa el binario sin patch).
#
# Requisitos: gcc, openssl-devel (o compat), pkg-config, cargo/rust
# En Fedora: sudo dnf install gcc openssl-devel pkg-config cargo
set -euo pipefail

REPO="https://github.com/feschber/lan-mouse.git"
TAG="${1:-v0.11.0}"
PATCH_DIR="$(dirname "$(realpath "$0")")/../patches"
PATCH="$PATCH_DIR/lan-mouse-altgr.patch"
BUILD_DIR="/tmp/lan-mouse-build"

if [[ ! -f "$PATCH" ]]; then
    echo "ERROR: patch no encontrado en $PATCH"
    exit 1
fi

# Verificar dependencias
for cmd in git cargo gcc pkg-config; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' no encontrado. Instalar con:"
        echo "  sudo dnf install gcc openssl-devel pkg-config cargo"
        exit 1
    fi
done

echo "==> Clonando lan-mouse ($TAG)..."
rm -rf "$BUILD_DIR"
git clone --depth 1 --branch "$TAG" "$REPO" "$BUILD_DIR"

echo "==> Aplicando patch de AltGr..."
cd "$BUILD_DIR"
git apply "$PATCH"

echo "==> Compilando (release)..."
cargo build --release

echo "==> Instalando a ~/.local/bin/..."
mkdir -p "$HOME/.local/bin"
cp target/release/lan-mouse "$HOME/.local/bin/lan-mouse"
chmod +x "$HOME/.local/bin/lan-mouse"

echo "==> ¡Listo! lan-mouse parcheado instalado en ~/.local/bin/lan-mouse"
echo "    Reiniciar el daemon: systemctl --user restart lan-mouse"
echo "    (o matar y re-ejecutar 'lan-mouse daemon')"

echo "==> Limpiando build dir..."
rm -rf "$BUILD_DIR"
