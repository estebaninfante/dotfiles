#!/usr/bin/env bash
set -uo pipefail

rc=0
ok() { printf 'OK\t%s\t%s\n' "$1" "$2"; }
fail() { printf 'FAIL\t%s\t%s\n' "$1" "$2"; rc=1; }
skip() { printf 'SKIP\t%s\t%s\n' "$1" "$2"; }

targets=()
for arg in "$@"; do
  case "$arg" in
    --probe)
      printf 'OK\tprobe\tsystemd\n'
      exit 0
      ;;
    *) targets+=("$arg") ;;
  esac
done

if ! command -v systemctl >/dev/null 2>&1; then
  skip "systemctl" "no instalado"
  exit "$rc"
fi

if [ "${VERIFY_ACTIVATE:-0}" = "1" ]; then
  if systemctl --user daemon-reload >/dev/null 2>&1; then
    ok "daemon-reload" "ok"
  else
    fail "daemon-reload" "fallo"
  fi
fi

for target in "${targets[@]}"; do
  base=$(basename "$target")
  if [[ "$base" == *.sh ]]; then
    if command -v shellcheck >/dev/null 2>&1; then
      if shellcheck "$target" >/dev/null 2>&1; then
        ok "shellcheck:$base" "limpio"
      else
        fail "shellcheck:$base" "$(shellcheck "$target" 2>&1 | head -n2 | tr '\n' ' ')"
      fi
    else
      skip "shellcheck:$base" "shellcheck no instalado"
    fi
    selftest_out=$("$target" --selftest 2>&1)
    if [ $? -eq 0 ]; then
      ok "selftest:$base" "ok"
    else
      fail "selftest:$base" "$(printf '%s' "$selftest_out" | head -n2 | tr '\n' ' ')"
    fi
    continue
  fi
  verify_out=$(systemd-analyze verify "$target" 2>&1)
  if [ $? -eq 0 ]; then
    ok "unit:$base" "valido"
  else
    fail "unit:$base" "$(printf '%s' "$verify_out" | head -n2 | tr '\n' ' ')"
  fi
  state=$(systemctl --user is-active "$base" 2>/dev/null || true)
  case "$state" in
    active|activating) ok "estado:$base" "$state" ;;
    *) skip "estado:$base" "${state:-desconocido}" ;;
  esac
done

exit "$rc"
