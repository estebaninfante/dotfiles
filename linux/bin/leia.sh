#!/usr/bin/env bash
set -euo pipefail

LEIA_DIR="$HOME/developing/leia"
PORT="${LEIA_PORT:-3100}"

# Reiniciar leia si ya está corriendo
if pgrep -f "dist-electron/main.js" > /dev/null; then
    pkill -f "dist-electron/main.js" || true
    sleep 0.5
fi

cd "$LEIA_DIR"

if ! curl -sf "http://127.0.0.1:$PORT" > /dev/null 2>&1; then
    # Servidor Next apagado: arrancar todo
    exec pnpm dev:desktop
else
    # Servidor ya corriendo: lanzar solo Electron
    npx tsc -p electron/tsconfig.json
    exec npx electron dist-electron/main.js
fi