#!/usr/bin/env bash
# ── cuda-error-loop.sh ──
# Loop infinito: corre CUDA rebuild, si falla lanza opencode para auto-fix,
# luego reintenta. Se detiene solo cuando el build tiene éxito.
#
# Uso:
#   bash ~/dotfiles/scripts/cuda-error-loop.sh           # loop infinito
#   bash ~/dotfiles/scripts/cuda-error-loop.sh --once    # un solo intento + fix
#   bash ~/dotfiles/scripts/cuda-error-loop.sh --status  # ver estado
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$HOME/.local/state/dotfiles"
STATUS_FILE="$LOG_DIR/cuda-rebuild-status"
ERROR_FILE="$LOG_DIR/cuda-rebuild-error"
LOOP_LOG="$LOG_DIR/cuda-error-loop.log"
MAX_FIX_ATTEMPTS="${MAX_FIX_ATTEMPTS:-3}"
ONCE=false

[[ "${1:-}" == "--once" ]] && ONCE=true
[[ "${1:-}" == "--status" ]] && { cat "$STATUS_FILE" 2>/dev/null || echo "No status"; exit 0; }

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg" | tee -a "$LOOP_LOG"
}

# ── Check if build is already running ──
build_running() {
  pgrep -f "cuda-rebuild.sh" >/dev/null 2>&1 || \
  pgrep -f "nixos-rebuild.*desktop" >/dev/null 2>&1
}

# ── Run build and wait ──
run_build() {
  log "Starting CUDA rebuild..."
  bash "$REPO/scripts/cuda-rebuild.sh" switch >> "$LOOP_LOG" 2>&1
  local rc=$?
  log "Build exited with code $rc"
  return $rc
}

# ── Analyze error and try auto-fix ──
auto_fix() {
  local error_content
  error_content=$(cat "$ERROR_FILE" 2>/dev/null || echo "No error file")

  log "Auto-fix: analyzing error..."
  log "Error content (last 30 lines):"
  echo "$error_content" | tail -30 >> "$LOOP_LOG"

  # Common NixOS CUDA fixes
  local fixed=false

  # 1. Disk space check
  local avail_gb
  avail_gb=$(df -BG /nix | awk 'NR==2{print $4}' | tr -d 'G')
  if [[ "$avail_gb" -lt 20 ]]; then
    log "Fix: low disk space (${avail_gb}GB). Running nix-collect-garbage..."
    nix-collect-garbage --delete-older-than 1d >> "$LOOP_LOG" 2>&1
    fixed=true
  fi

  # 2. Check for corrupted store paths
  if grep -q "Corrupted store path\|incorrect size\|hash mismatch" "$ERROR_FILE" 2>/dev/null; then
    log "Fix: corrupted store paths detected. Running nix-store --verify..."
    nix-store --verify --check-contents >> "$LOOP_LOG" 2>&1 || true
    # Repair if possible
    nix-store --repair --check-contents >> "$LOOP_LOG" 2>&1 || true
    fixed=true
  fi

  # 3. Check for "no space left on device" in build chroot
  if grep -q "No space left on device" "$ERROR_FILE" 2>/dev/null; then
    log "Fix: no space in build chroot. Cleaning /tmp and nix-daemon cache..."
    rm -rf /tmp/nix-build-* 2>/dev/null || true
    sudo systemctl restart nix-daemon >> "$LOOP_LOG" 2>&1 || true
    fixed=true
  fi

  # 4. Check for OOM
  if grep -qi "Out of memory\|oom\|Cannot allocate" "$ERROR_FILE" 2>/dev/null; then
    log "Fix: OOM detected. Reducing parallelism..."
    export NIX_CONFIG="max-jobs = 1"$'\n'"cores = 4"
    fixed=true
  fi

  # 5. Check for specific package build failures and try to skip/fix
  if grep -q "error: build of.*failed" "$ERROR_FILE" 2>/dev/null; then
    local failed_pkg
    failed_pkg=$(grep -oP "error: build of '\K[^']*" "$ERROR_FILE" 2>/dev/null | head -1)
    if [[ -n "$failed_pkg" ]]; then
      log "Fix: specific package failed: $failed_pkg"
      # Try to find and fix the nix expression
      local pkg_name
      pkg_name=$(basename "$failed_pkg" | sed 's/-[0-9].*//')
      log "Looking for nix expression for: $pkg_name"

      # Search in nixos/modules/packages.nix and desktop.nix
      if grep -q "$pkg_name" "$REPO/nixos/modules/packages.nix" 2>/dev/null; then
        log "Found in packages.nix - may need to adjust version or override"
      fi
    fi
  fi

  # 6. If no specific fix, try opencode
  if [[ "$fixed" == "false" ]]; then
    log "No automatic fix found. Launching opencode for analysis..."

    # Build the prompt for opencode
    local prompt="CUDA build failed. Error log: $ERROR_FILE. Recent errors:

$(tail -50 "$ERROR_FILE" 2>/dev/null || echo 'No error content')

System info:
- Disk: $(df -h /nix | awk 'NR==2{print $4}') free
- RAM: $(free -h | awk '/Mem:/{print $7}') available
- NixOS generation: $(nix-env --list-generations 2>/dev/null | grep current | awk '{print $1}')

Analyze the error, find the root cause, and fix the nix configuration in ~/dotfiles/.
Then run: bash ~/dotfiles/scripts/cuda-rebuild.sh switch
Report what you fixed."

    # Run opencode non-interactive
    if command -v opencode &>/dev/null; then
      cd "$REPO"
      opencode run --agent dotfiles "$prompt" >> "$LOOP_LOG" 2>&1
      log "opencode completed. Checking if fix was applied..."
    else
      log "ERROR: opencode not found in PATH"
    fi
  fi

  return 0
}

# ── Main loop ──
log "═══════════════════════════════════════════════════════════════"
log " CUDA Error Loop started"
log " Mode: $(if $ONCE; then echo 'once'; else echo 'infinite'; fi)"
log " MAX_FIX_ATTEMPTS: $MAX_FIX_ATTEMPTS"
log "═══════════════════════════════════════════════════════════════"

# Kill any existing build first
if build_running; then
  log "Existing build detected. Waiting for it to finish..."
  while build_running; do
    sleep 10
  done
  log "Previous build finished."
fi

fix_attempts=0
while true; do
  # Run build
  if run_build; then
    log "✓ BUILD SUCCESSFUL!"
    log "═══════════════════════════════════════════════════════════════"

    # Notify user
    if command -v notify-send &>/dev/null; then
      notify-send -u critical "CUDA Build" "Build exitoso! ✅" 2>/dev/null || true
    fi

    $ONCE && exit 0
    log "Stopping loop (build succeeded)."
    exit 0
  fi

  # Build failed
  fix_attempts=$((fix_attempts + 1))
  log "Build failed (attempt $fix_attempts/$MAX_FIX_ATTEMPTS)"

  if [[ $fix_attempts -ge $MAX_FIX_ATTEMPTS ]]; then
    log "Max fix attempts reached. Manual intervention needed."
    log "Check: $ERROR_FILE"
    log "Check: $LOOP_LOG"

    # Notify user
    if command -v notify-send &>/dev/null; then
      notify-send -u critical "CUDA Build" "Build falló $MAX_FIX_ATTEMPTS veces. Revisa logs." 2>/dev/null || true
    fi

    $ONCE && exit 1
    # In infinite mode, wait longer before retrying
    log "Waiting 60s before final retry..."
    sleep 60
    fix_attempts=0  # Reset after long wait
    continue
  fi

  # Auto-fix
  auto_fix

  log "Waiting 10s before retry..."
  sleep 10
done
