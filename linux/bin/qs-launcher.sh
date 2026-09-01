#!/usr/bin/env bash

# Abre/cierra el launcher de quickshell via IPC. Toggle: si el modo ya está
# abierto se cierra; si está abierto otro modo, cambia a este.
# Uso: qs-launcher.sh [apps|files|scripts] (default: apps)
set -euo pipefail

MODE="${1:-apps}"
exec qs ipc call launcher toggle "$MODE"