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
      printf 'OK\tprobe\thyprland\n'
      exit 0
      ;;
    *) targets+=("$arg") ;;
  esac
done

if ! command -v hyprctl >/dev/null 2>&1; then
  skip "hyprctl" "no instalado"
  exit "$rc"
fi

if ! hyprctl version >/dev/null 2>&1; then
  fail "hyprctl" "no responde (compositor apagado?)"
  exit "$rc"
fi
ok "hyprctl" "$(hyprctl version | head -n1)"

if [ "${VERIFY_ACTIVATE:-0}" = "1" ]; then
  if hyprctl reload >/dev/null 2>&1; then
    ok "reload" "hyprctl reload"
  else
    fail "reload" "hyprctl reload fallo"
  fi
fi

errors=$(hyprctl configerrors 2>/dev/null)
if [ -z "$errors" ]; then
  ok "configerrors" "sin errores"
else
  fail "configerrors" "$(printf '%s' "$errors" | head -n3 | tr '\n' ' ')"
fi

for target in "${targets[@]}"; do
  case "$target" in
    *.lua)
      if command -v luac >/dev/null 2>&1; then
        if luac -p "$target" >/dev/null 2>&1; then
          ok "lua:$(basename "$target")" "sintaxis ok"
        else
          fail "lua:$(basename "$target")" "$(luac -p "$target" 2>&1 | head -n1)"
        fi
      else
        skip "lua:$(basename "$target")" "luac ausente"
      fi
      ;;
  esac
done

exit "$rc"
