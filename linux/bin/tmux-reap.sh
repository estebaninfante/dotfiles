#!/usr/bin/env bash
set -euo pipefail

REAP_HOURS="${TMUX_REAP_HOURS:-2}"
REAP_FILTER="${TMUX_REAP_FILTER:-}"
SELFTEST=0

usage() {
  echo "usage: tmux-reap.sh [--selftest]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) SELFTEST=1 ;;
    *) usage ;;
  esac
  shift
done

if ! [[ "$REAP_HOURS" =~ ^[0-9]+$ ]]; then
  echo "tmux-reap: TMUX_REAP_HOURS must be a non-negative integer" >&2
  exit 1
fi

command -v tmux >/dev/null 2>&1 || exit 0

reap() {
  local now threshold format name attached activity reaped=0
  now=$(date +%s)
  threshold=$((REAP_HOURS * 3600))
  format=$'#{session_name}\t#{session_attached}\t#{session_activity}'

  while IFS=$'\t' read -r name attached activity; do
    [[ -n "$name" ]] || continue
    [[ "$attached" =~ ^[0-9]+$ && "$activity" =~ ^[0-9]+$ ]] || continue
    if [[ -n "$REAP_FILTER" ]] && ! [[ "$name" =~ $REAP_FILTER ]]; then
      continue
    fi
    ((attached > 0)) && continue
    ((now - activity >= threshold)) || continue
    if tmux kill-session -t "$name" 2>/dev/null; then
      echo "tmux-reap: reaped $name (idle $(( (now - activity) / 3600 ))h)"
      reaped=$((reaped + 1))
    fi
  done < <(tmux list-sessions -F "$format" 2>/dev/null || true)

  echo "tmux-reap: done reaped=$reaped threshold_hours=$REAP_HOURS"
}

selftest() {
  local session="_reap_selftest"
  tmux kill-session -t "$session" 2>/dev/null || true
  if ! tmux new-session -d -s "$session"; then
    echo "tmux-reap selftest FAIL: cannot create test session" >&2
    exit 1
  fi
  REAP_HOURS=0
  REAP_FILTER="^${session}$"
  reap
  if tmux has-session -t "$session" 2>/dev/null; then
    tmux kill-session -t "$session" 2>/dev/null || true
    echo "tmux-reap selftest FAIL: test session survived" >&2
    exit 1
  fi
  echo "tmux-reap selftest OK"
}

if [ "$SELFTEST" = "1" ]; then
  selftest
else
  reap
fi
