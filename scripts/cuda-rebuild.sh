#!/usr/bin/env bash
# ── cuda-rebuild.sh ──
# CUDA rebuild con loop de reintentos y logging para opencode.
# Captura errores y los escribe en un archivo que opencode puede analizar
# para hacer auto-fix y reintentar.
#
# Uso:
#   bash ~/dotfiles/scripts/cuda-rebuild.sh           # rebuild con retry loop
#   bash ~/dotfiles/scripts/cuda-rebuild.sh dry-build  # solo evaluar
#   bash ~/dotfiles/scripts/cuda-rebuild.sh --status   # ver estado actual
#
# Env vars:
#   MAX_RETRIES=5        # maximo de reintentos (default 5)
#   NIX_CONFIG overrides  # paralelismo custom
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$HOME/.local/state/dotfiles"
LOG_FILE="$LOG_DIR/cuda-rebuild.log"
ERROR_FILE="$LOG_DIR/cuda-rebuild-error"
STATUS_FILE="$LOG_DIR/cuda-rebuild-status"
MAX_RETRIES="${MAX_RETRIES:-5}"

ACTION="${1:-switch}"

mkdir -p "$LOG_DIR"

# ── Status mode ──
if [ "$ACTION" = "--status" ]; then
  if [ -f "$STATUS_FILE" ]; then
    cat "$STATUS_FILE"
  else
    echo "No previous CUDA rebuild found."
  fi
  exit 0
fi

case "$ACTION" in
  switch|boot|test|build|dry-build|dry-activate) ;;
  *)
    echo "ERROR: accion '$ACTION' no soportada" >&2
    echo "Uso: cuda-rebuild.sh [switch|dry-build|boot|test|build]" >&2
    exit 1
    ;;
esac

# ── Init status ──
echo "status=running" > "$STATUS_FILE"
echo "action=$ACTION" >> "$STATUS_FILE"
echo "start=$(date -Iseconds)" >> "$STATUS_FILE"
echo "attempt=1" >> "$STATUS_FILE"
echo "" > "$ERROR_FILE"

# ── NIX_CONFIG: paralelismo conservador ──
# max-jobs=1: un solo job paralelo (torch/onnxruntime comen ~8-12GB cada uno)
# cores=4: limita cores por job para no saturar RAM
# Override: NIX_CONFIG="max-jobs = 2"$'\n'"cores = 8" bash cuda-rebuild.sh
if [ -z "${NIX_CONFIG:-}" ]; then
  export NIX_CONFIG="max-jobs = 1"$'\n'"cores = 4"
fi

# ── Stop heavy services (optional: STOP_SERVICES=1) ──
if [ "${STOP_SERVICES:-0}" = "1" ]; then
  echo " Deteniendo servicios pesados para liberar RAM..."
  for svc in syncthing tailscaled lan-mouse sunshine; do
    systemctl --user stop "$svc.service" 2>/dev/null && echo "  ✓ $svc stopped" || true
  done
  # Stop docker if running (can eat RAM)
  systemctl stop docker.socket docker.service 2>/dev/null && echo "  ✓ docker stopped" || true
fi

echo "═══════════════════════════════════════════════════════════════"
echo " CUDA Rebuild — $(date)"
echo " NIX_CONFIG: $NIX_CONFIG"
echo " MAX_RETRIES: $MAX_RETRIES"
echo " Log: $LOG_FILE"
echo "═══════════════════════════════════════════════════════════════"

for attempt in $(seq 1 "$MAX_RETRIES"); do
  echo "" >> "$LOG_FILE"
  echo "── Attempt $attempt/$MAX_RETRIES — $(date) ──" >> "$LOG_FILE"

  # Clear previous error
  : > "$ERROR_FILE"

  echo ""
  echo " Starting build at $(date) — attempt $attempt/$MAX_RETRIES"

  # Run rebuild, capture both stdout and stderr
  if NIX_CONFIG="$NIX_CONFIG" bash "$REPO/scripts/rebuild.sh" "$ACTION" \
    2>&1 | tee -a "$LOG_FILE"; then
    # Success
    echo "status=success" > "$STATUS_FILE"
    echo "end=$(date -Iseconds)" >> "$STATUS_FILE"
    echo "attempts=$attempt" >> "$STATUS_FILE"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo " ✓ CUDA rebuild EXITOSO en intento $attempt"
    echo "═══════════════════════════════════════════════════════════════"
    exit 0
  fi

  BUILD_EXIT=$?

  # Capture last 50 lines of error for opencode
  tail -50 "$LOG_FILE" > "$ERROR_FILE"

  echo "status=failed" > "$STATUS_FILE"
  echo "attempt=$attempt" >> "$STATUS_FILE"
  echo "exit_code=$BUILD_EXIT" >> "$STATUS_FILE"
  echo "last_error=$(date -Iseconds)" >> "$STATUS_FILE"

  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo " ✗ Intento $attempt FALLÓ (exit code: $BUILD_EXIT)"
  echo " Error capturado en: $ERROR_FILE"
  echo "═══════════════════════════════════════════════════════════════"

  if [ "$attempt" -lt "$MAX_RETRIES" ]; then
    echo " Reintentando en 5 segundos..."
    sleep 5
  fi
done

echo "status=max_retries" > "$STATUS_FILE"
echo "end=$(date -Iseconds)" >> "$STATUS_FILE"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " ✗ Max retries ($MAX_RETRIES) alcanzado. Revisa:"
echo "   $LOG_FILE"
echo "   $ERROR_FILE"
echo "═══════════════════════════════════════════════════════════════"
exit 1
