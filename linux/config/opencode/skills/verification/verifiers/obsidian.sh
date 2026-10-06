#!/usr/bin/env bash
set -uo pipefail

DOMAIN=obsidian
VAULT="${ALICIA_VAULT:-$HOME/alicia}"

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

if [[ ${#targets[@]} -eq 0 ]]; then
  targets=("$HOME/dotfiles/linux/bin/obsidian-note")
fi

for target in "${targets[@]}"; do
  base=$(basename "$target")
  if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$target" >/dev/null 2>&1; then
      ok "shellcheck:$base" "limpio"
    else
      fail "shellcheck:$base" "$(shellcheck "$target" 2>&1 | head -n2 | tr '\n' ' ')"
    fi
  else
    skip "shellcheck:$base" "shellcheck no instalado"
  fi
  if selftest_out=$("$target" --selftest 2>&1); then
    ok "selftest:$base" "ok"
  else
    fail "selftest:$base" "$(printf '%s' "$selftest_out" | head -n2 | tr '\n' ' ')"
  fi
done

link="$HOME/.local/bin/obsidian-note"
if [ -L "$link" ]; then
  if [ -x "$(readlink -f "$link")" ]; then
    ok "symlink" "$link -> $(readlink "$link")"
  else
    fail "symlink" "$link apunta a archivo inexistente"
  fi
else
  fail "symlink" "$link no existe"
fi

for dir in Inbox Proyectos Areas Daily Archivo; do
  if [ -d "$VAULT/$dir" ]; then
    ok "vault:$dir" "$VAULT/$dir"
  else
    fail "vault:$dir" "falta $VAULT/$dir"
  fi
done

exit "$rc"
