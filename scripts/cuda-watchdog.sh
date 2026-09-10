#!/usr/bin/env bash
# ── cuda-watchdog.sh ──
# Checks CUDA build every 30 min. If stuck, kills and restarts.
set -uo pipefail

LOG_DIR="$HOME/.local/state/dotfiles"
STATUS_FILE="$LOG_DIR/cuda-rebuild-status"
LOG_FILE="$LOG_DIR/cuda-rebuild.log"
WATCHDOG_LOG="$LOG_DIR/cuda-watchdog.log"
STUCK_MARKER="$LOG_DIR/cuda-watchdog-stuck"
REPO="$HOME/dotfiles"

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$WATCHDOG_LOG"; }

# Check 1: Is a build running?
BUILD_RUNNING=0
pgrep -f "nixos-rebuild" > /dev/null 2>&1 && BUILD_RUNNING=1
pgrep -f "nixbld" > /dev/null 2>&1 && BUILD_RUNNING=1
pgrep -f "clang++" > /dev/null 2>&1 && BUILD_RUNNING=1

if [ "$BUILD_RUNNING" -eq 0 ]; then
  STATUS=$(rtk cat "$STATUS_FILE" 2>/dev/null | grep "^status=" | cut -d= -f2)
  if [ "$STATUS" = "success" ]; then
    log "BUILD DONE (success). Watchdog exiting."
    exit 0
  fi
  log "NO BUILD RUNNING. Status=$STATUS. Would need restart."
  # Write stuck marker so opencode can see it
  echo "no_build=$(date -Iseconds)" > "$STUCK_MARKER"
  exit 1
fi

# Check 2: Are compilers actually working? (not just nix-daemon idle)
COMPILE_PROCS=$(ps aux | grep -E "(cc1plus|cc1|clang\+\+|nvcc|g\+\+)" | grep -v grep | wc -l)
NIXBLD_MEM=$(ps aux | awk '/nixbld/ {sum+=$6} END {print int(sum/1024)}')
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')

# Check 3: Has the log progressed? (new "building" lines in last 30 min)
LOG_LINES_NOW=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
sleep 5
LOG_LINES_AFTER=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
LOG_GROWTH=$((LOG_LINES_AFTER - LOG_LINES_NOW))

# Check 4: Any process in D state (stuck IO)?
D_STATE=$(ps aux | awk '$8 ~ /D/' | wc -l)

log "Procs=$COMPILE_PROCS Mem=${NIXBLD_MEM}MB Load=$LOAD LogGrowth=$LOG_GROWTH D-state=$D_STATE"

# Stuck detection: no compilers running OR no log growth after 30 min AND load < 2
if [ "$COMPILE_PROCS" -lt 1 ] && [ "$LOG_GROWTH" -lt 2 ] && [ "$(echo "$LOAD < 2" | bc 2>/dev/null || echo 1)" = "1" ]; then
  log "STUCK DETECTED: 0 compilers, log not growing, load low."
  echo "stuck=$(date -Iseconds) procs=$COMPILE_PROCS load=$LOAD" > "$STUCK_MARKER"
  # Kill everything and let cuda-rebuild.sh retry
  log "Killing stuck build for retry..."
  pkill -9 -f "nixos-rebuild" 2>/dev/null
  pkill -9 -f "nixbld" 2>/dev/null
  sleep 5
  # Restart via cuda-rebuild.sh
  log "Restarting build..."
  nohup bash -c 'MAX_RETRIES=3 bash ~/dotfiles/scripts/cuda-rebuild.sh switch' \
    >> "$LOG_FILE" 2>&1 &
  log "Restarted (PID $!)"
else
  log "BUILD OK: $COMPILE_PROCS compilers active, load=$LOAD"
  [ -f "$STUCK_MARKER" ] && rm "$STUCK_MARKER"
fi
