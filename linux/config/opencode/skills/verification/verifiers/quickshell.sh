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
      printf 'OK\tprobe\tquickshell\n'
      exit 0
      ;;
    *) targets+=("$arg") ;;
  esac
done

if [ "${VERIFY_ACTIVATE:-0}" = "1" ]; then
  if omarchy restart shell >/dev/null 2>&1; then
    sleep 3
    ok "activar" "omarchy restart shell"
  else
    fail "activar" "omarchy restart shell fallo"
  fi
fi

shell_pattern='quickshell -n -p /usr/share/omarchy/shell'
if pgrep -f "$shell_pattern" >/dev/null 2>&1; then
  ok "shell-proceso" "pid $(pgrep -f "$shell_pattern" | head -n1)"
else
  fail "shell-proceso" "quickshell no esta corriendo"
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  if omarchy-shell -q shell ping >/dev/null 2>&1; then
    ok "shell-ipc" "ping responde"
  else
    fail "shell-ipc" "ping sin respuesta"
  fi
else
  skip "shell-ipc" "omarchy-shell ausente"
fi

qml=()
for target in "${targets[@]}"; do
  case "$target" in
    *.qml)
      qml+=("$target")
      ;;
    *.json)
      if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$target" 2>/dev/null; then
        ok "json:$(basename "$target")" "valido"
      else
        fail "json:$(basename "$target")" "JSON invalido"
      fi
      ;;
  esac
done

if [ "${#qml[@]}" -gt 0 ]; then
  if command -v omarchy-qml-lint >/dev/null 2>&1; then
    lint_out=$(omarchy-qml-lint --quiet "${qml[@]}" 2>&1)
    lint_rc=$?
    if [ "$lint_rc" -eq 0 ]; then
      if [ -z "$lint_out" ]; then
        ok "qml-lint" "${#qml[@]} archivo/s limpios"
      else
        ok "qml-lint" "$(printf '%s' "$lint_out" | head -n1)"
      fi
    else
      fail "qml-lint" "$(printf '%s' "$lint_out" | head -n3 | tr '\n' ' ')"
    fi
  else
    skip "qml-lint" "omarchy-qml-lint ausente"
  fi
fi

exit "$rc"
