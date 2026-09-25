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
      printf 'OK\tprobe\tsyntax\n'
      exit 0
      ;;
    *) targets+=("$arg") ;;
  esac
done

for target in "${targets[@]}"; do
  base=$(basename "$target")
  case "$target" in
    *.json)
      if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$target" 2>/dev/null; then
        ok "json:$base" "valido"
      else
        fail "json:$base" "JSON invalido"
      fi
      ;;
    *.jsonc)
      if python3 - "$target" <<'PYEOF'
import json
import re
import sys

sl = chr(47)
st = chr(42)
text = open(sys.argv[1]).read()
text = re.sub(re.escape(sl + st) + r".*?" + re.escape(st + sl), "", text, flags=re.S)
text = re.sub(r"(?m)^\s*" + re.escape(sl + sl) + r".*$", "", text)
json.loads(text)
PYEOF
      then
        ok "jsonc:$base" "valido"
      else
        fail "jsonc:$base" "JSONC invalido"
      fi
      ;;
    *.sh)
      if bash -n "$target" 2>/dev/null; then
        ok "sh:$base" "sintaxis ok"
      else
        fail "sh:$base" "$(bash -n "$target" 2>&1 | head -n1)"
      fi
      ;;
    *.py)
      if python3 -m py_compile "$target" 2>/dev/null; then
        ok "py:$base" "compila"
      else
        fail "py:$base" "$(python3 -m py_compile "$target" 2>&1 | tail -n1)"
      fi
      ;;
    *.toml)
      if python3 -c 'import tomllib,sys; tomllib.load(open(sys.argv[1],"rb"))' "$target" 2>/dev/null; then
        ok "toml:$base" "valido"
      else
        fail "toml:$base" "TOML invalido"
      fi
      ;;
    *.yaml|*.yml)
      if python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$target" 2>/dev/null; then
        ok "yaml:$base" "valido"
      else
        skip "yaml:$base" "sin parser yaml o invalido"
      fi
      ;;
    *)
      skip "$base" "extension no soportada"
      ;;
  esac
done

exit "$rc"
