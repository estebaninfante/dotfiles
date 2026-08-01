#!/usr/bin/env bash
set -euo pipefail

TEMP_DIR="$HOME/Descargas/temp"

if [ -d "$TEMP_DIR" ]; then
  find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi
