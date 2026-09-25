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
      printf 'OK\tprobe\tcode\n'
      exit 0
      ;;
    *) targets+=("$arg") ;;
  esac
done

find_root() {
  local dir=$1
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -f "$dir/package.json" ] || [ -f "$dir/pyproject.toml" ] || [ -f "$dir/Cargo.toml" ] || [ -f "$dir/go.mod" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 0
}

step() {
  local name=$1
  shift
  local out
  out=$(timeout "${VERIFY_TIMEOUT:-120}" "$@" 2>&1)
  local status=$?
  if [ "$status" -eq 0 ]; then
    ok "$name" "ok"
  else
    fail "$name" "$(printf '%s' "$out" | tail -n3 | tr '\n' ' ')"
  fi
}

roots=()
for target in "${targets[@]}"; do
  root=$(find_root "$(dirname "$target")")
  [ -n "$root" ] && roots+=("$root")
done

if [ "${#roots[@]}" -eq 0 ]; then
  skip "proyecto" "sin manifiesto conocido"
  exit "$rc"
fi

unique_roots=()
for root in "${roots[@]}"; do
  seen=0
  for existing in "${unique_roots[@]:-}"; do
    [ "$existing" = "$root" ] && seen=1
  done
  [ "$seen" -eq 0 ] && unique_roots+=("$root")
done

for root in "${unique_roots[@]}"; do
  tag=$(basename "$root")

  if [ -f "$root/package.json" ]; then
    if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$root/package.json" 2>/dev/null; then
      ok "json:$tag" "package.json valido"
    else
      fail "json:$tag" "package.json invalido"
      continue
    fi
    has_script() {
      python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sys.argv[2] in d.get("scripts",{}) else 1)' "$root/package.json" "$1"
    }
    has_script lint && step "lint:$tag" npm --prefix "$root" run --silent lint
    has_script typecheck && step "typecheck:$tag" npm --prefix "$root" run --silent typecheck
    has_script test && step "test:$tag" npm --prefix "$root" run --silent test
  fi

  if [ -f "$root/pyproject.toml" ]; then
    command -v ruff >/dev/null 2>&1 && step "ruff:$tag" ruff check "$root"
    command -v mypy >/dev/null 2>&1 && step "mypy:$tag" mypy "$root"
    command -v pytest >/dev/null 2>&1 && step "pytest:$tag" pytest -q "$root"
  fi

  if [ -f "$root/Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then
    step "clippy:$tag" cargo clippy --quiet --manifest-path "$root/Cargo.toml"
    step "cargo-test:$tag" cargo test --quiet --manifest-path "$root/Cargo.toml"
  fi

  if [ -f "$root/go.mod" ] && command -v go >/dev/null 2>&1; then
    step "go-vet:$tag" bash -c "cd \"$root\" && go vet ./..."
    step "go-test:$tag" bash -c "cd \"$root\" && go test ./..."
  fi
done

exit "$rc"
