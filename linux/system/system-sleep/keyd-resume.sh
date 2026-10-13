#!/usr/bin/env bash
set -uo pipefail

KEYD_UNIT="${KEYD_UNIT:-keyd.service}"
SYSTEMCTL="${SYSTEMCTL:-systemctl}"

restart_keyd() {
  if ! "$SYSTEMCTL" cat "$KEYD_UNIT" >/dev/null 2>&1; then
    return 0
  fi
  "$SYSTEMCTL" restart "$KEYD_UNIT"
}

selftest() {
  local out rc=0
  out="$(SYSTEMCTL=echo KEYD_UNIT=keyd.service "$0" post)"
  printf '%s\n' "$out" | grep -qx 'restart keyd.service' || rc=1
  out="$(SYSTEMCTL=echo KEYD_UNIT=keyd.service "$0" pre)"
  [ -z "$out" ] || rc=1
  [ "$rc" -eq 0 ] && printf 'selftest ok\n'
  return "$rc"
}

case "${1:-}" in
  post) restart_keyd ;;
  --selftest) selftest ;;
esac
