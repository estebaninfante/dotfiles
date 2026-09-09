#!/usr/bin/env bash
# handy-toggle.sh — toggle Handy dictation (with post-processing) from a gesture.
#
# Handy's real recording state is not exposed to the outside world, so this
# script mirrors the toggle into a state file that Quickshell's VoiceHalo
# polls. A *single* gesture fires this script exactly once (the gesture
# debouncer no longer double-fires), so the file stays in sync with Handy.
#
# The state file is a simple "exists == recording" flag:
#   ~/.local/state/voice/handy-active
set -euo pipefail

STATE="${HANDY_STATE_FILE:-$HOME/.local/state/voice/handy-active}"

# Toggle Handy. Sent to the already-running instance; if it is not running,
# this launches the hidden instance (the toggle is only honoured by a running
# instance, so keep Handy started — e.g. via the tray or --start-hidden).
handy --toggle-post-process

# Mirror the toggle on/off.
if [ -e "$STATE" ]; then
  rm -f "$STATE"
else
  mkdir -p "$(dirname "$STATE")"
  touch "$STATE"
fi
