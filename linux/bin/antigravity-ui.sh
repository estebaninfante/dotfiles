#!/usr/bin/env bash

# Lanzador de la Aplicación GUI Antigravity Agent

UI_DIR="$HOME/developing/antigravity-ui"

# Si el servidor no está corriendo, iniciarlo en segundo plano
if ! pgrep -f "node server.js" > /dev/null; then
    ( cd "$UI_DIR" && node server.js > /dev/null 2>&1 & )
    sleep 1
fi

# Abrir en modo aplicación flotante con Firefox o navegador predeterminado
if command -v firefox >/dev/null 2>&1; then
    firefox --new-window http://localhost:3333
else
    xdg-open http://localhost:3333
fi
