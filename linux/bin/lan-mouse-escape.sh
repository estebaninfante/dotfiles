#!/usr/bin/env bash
# Emergency escape: kill lan-mouse + restart quickshell
# Run from TTY (Ctrl+Alt+F2) if input is stuck
set -euo pipefail

echo "=== lan-mouse emergency escape ==="

# Kill lan-mouse daemon
if pgrep -x lan-mouse > /dev/null 2>&1; then
    pkill -x lan-mouse
    echo "[OK] lan-mouse killed"
else
    echo "[SKIP] lan-mouse not running"
fi

# Stop the systemd service to prevent respawn
systemctl --user stop lan-mouse.service 2>/dev/null && echo "[OK] service stopped" || echo "[SKIP] service already stopped"

# Restart quickshell if it died
if ! pgrep -x quickshell > /dev/null 2>&1; then
    quickshell --no-duplicate &
    echo "[OK] quickshell restarted"
else
    echo "[SKIP] quickshell running"
fi

echo "Switch back to graphical TTY (Ctrl+Alt+F1 or loginctl activate <session>)"
