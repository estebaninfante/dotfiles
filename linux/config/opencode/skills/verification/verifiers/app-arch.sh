#!/usr/bin/env bash
set -uo pipefail

DOMAIN=app-arch
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LINTER=${HOME}/.local/bin/app-arch-lint

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

if [ ! -x "$LINTER" ]; then
  skip "linter" "app-arch-lint ausente"
  exit "$rc"
fi

is_bin_script() {
  case "$(basename "$1")" in
    new-app|app-arch-lint) return 0 ;;
    *) return 1 ;;
  esac
}

find_root() {
  local p=$1 d
  if [ -d "$p" ]; then
    d=$p
  else
    d=$(dirname "$p")
  fi
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    if [ -f "$d/package.json" ] || [ -f "$d/pyproject.toml" ] || [ -f "$d/Cargo.toml" ] \
      || [ -f "$d/go.mod" ] || [ -d "$d/.git" ] || [ -f "$d/index.html" ] \
      || [ -f "$d/public/index.html" ] || [ -f "$d/static/index.html" ]; then
      printf '%s\n' "$d"
      return 0
    fi
    d=$(dirname "$d")
  done
  printf '%s\n' "$d"
}

emit_tsv() {
  local st name detail
  while IFS=$'\t' read -r st name detail; do
    [ -n "$st" ] || continue
    case "$st" in
      OK) ok "$name" "$detail" ;;
      FAIL) fail "$name" "$detail" ;;
      *) skip "$name" "$detail" ;;
    esac
  done
}

for target in "${targets[@]}"; do
  base=$(basename "$target")

  if is_bin_script "$target"; then
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
    continue
  fi

  if [ ! -e "$target" ]; then
    skip "$base" "no existe"
    continue
  fi

  lint_out=$("$LINTER" --tsv "$target" 2>&1)
  if [ -n "$lint_out" ]; then
    printf '%s\n' "$lint_out" | emit_tsv
  else
    skip "$base" "sin senal de app"
  fi

  root=$(find_root "$target")
  if [ -n "$root" ] && [ -f "$root/package.json" ] && [ -d "$root/node_modules" ] && [ -x "$SCRIPT_DIR/code.sh" ]; then
    code_target=$target
    if [ -d "$target" ]; then
      code_target="$target/package.json"
    fi
    code_out=$(timeout "${VERIFY_TIMEOUT:-120}" "$SCRIPT_DIR/code.sh" "$code_target" 2>/dev/null)
    if [ -n "$code_out" ]; then
      printf '%s\n' "$code_out" | emit_tsv
    fi
  fi
done

exit "$rc"
