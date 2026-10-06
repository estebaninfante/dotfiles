#!/usr/bin/env bash
set -uo pipefail

DOMAIN=uiux
ROOT="$HOME/.config/opencode/skills/ui-ux-scorer"
AGENT="$HOME/.config/opencode/agents/ui-ux.md"

rc=0
ok() { printf 'OK\t%s\t%s\n' "$1" "$2"; }
fail() { printf 'FAIL\t%s\t%s\n' "$1" "$2"; rc=1; }

for arg in "$@"; do
  case "$arg" in
    --probe)
      printf 'OK\tprobe\t%s\n' "$DOMAIN"
      exit 0
      ;;
  esac
done

if [[ ! -d "$ROOT" ]]; then
  fail "skill-root" "no existe $ROOT"
  exit "$rc"
fi
ok "skill-root" "$ROOT"

if [[ -s "$ROOT/SKILL.md" ]]; then
  ok "skill-doc" "SKILL.md"
else
  fail "skill-doc" "falta o vacio SKILL.md"
fi

if [[ -s "$AGENT" ]]; then
  ok "agent-doc" "agents/ui-ux.md"
else
  fail "agent-doc" "falta o vacio agents/ui-ux.md"
fi

syn_err=$(mktemp)
if node --check "$ROOT/probe.mjs" 2>"$syn_err"; then
  ok "probe-syntax" "probe.mjs"
else
  fail "probe-syntax" "$(tail -1 "$syn_err")"
fi
rm -f "$syn_err"

sel_out=$(mktemp)
sel_err=$(mktemp)
if timeout 90 node "$ROOT/probe.mjs" --selftest >"$sel_out" 2>"$sel_err" && \
   node -e '
const fs = require("fs")
const j = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
if (!j.ok) throw new Error("ok=false")
if (j.missing && j.missing.length) throw new Error("faltan: " + j.missing.join(","))
if (j.cleanFalsePositives) throw new Error("falsos positivos: " + j.cleanFalsePositives)
' "$sel_out"; then
  ok "probe-selftest" "checks detectados, 0 falsos positivos"
else
  fail "probe-selftest" "$(tail -1 "$sel_err" 2>/dev/null | head -c 200)"
fi
rm -f "$sel_out" "$sel_err"

exit "$rc"
