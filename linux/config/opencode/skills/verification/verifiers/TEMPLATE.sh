#!/usr/bin/env bash
set -uo pipefail

DOMAIN=DOMAIN_NAME

rc=0
ok() { printf 'OK\t%s\t%s\n' "$1" "$2"; }
fail() { printf 'FAIL\t%s\t%s\n' "$1" "$2"; rc=1; }
skip() { printf 'SKIP\t%s\t%s\n' "$1" "$2"; }

targets=()
for arg in "$@"; do
  case "$arg" in
    --probe)
      printf 'OK\tprobe\t%s\n' "$DOMAIN"
      exit 0
      ;;
    *) targets+=("$arg") ;;
  esac
done

skip "pendiente" "implementar checks para $DOMAIN (${#targets[@]} objetivo/s)"
exit "$rc"
