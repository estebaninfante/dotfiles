#!/usr/bin/env bash
set -uo pipefail

DOMAIN=browser
ROOT="$HOME/.config/opencode/skills/browser-pilot"

rc=0
ok() { printf 'OK\t%s\t%s\n' "$1" "$2"; }
fail() { printf 'FAIL\t%s\t%s\n' "$1" "$2"; rc=1; }
skip() { printf 'SKIP\t%s\t%s\n' "$1" "$2"; }

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

sel_err=$(mktemp)
if node -e '
const fs = require("fs")
const s = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
for (const k of ["youtube", "x"]) {
  if (!s[k]) throw new Error("falta " + k)
  if (!Array.isArray(s[k].patterns) || !s[k].patterns.length) throw new Error(k + ".patterns")
  if (!s[k].selectors || !Object.keys(s[k].selectors).length) throw new Error(k + ".selectors")
}
' "$ROOT/selectors.json" 2>"$sel_err"; then
  ok "selectors-schema" "youtube+x con patterns/selectors"
else
  fail "selectors-schema" "$(tail -1 "$sel_err")"
fi
rm -f "$sel_err"

syn_ok=1
syn_err=$(mktemp)
for f in pilot tasks runlog; do
  if ! node --check "$ROOT/lib/$f.mjs" 2>"$syn_err"; then
    fail "lib-syntax:$f" "$(tail -1 "$syn_err")"
    syn_ok=0
  fi
done
rm -f "$syn_err"
[[ "$syn_ok" -eq 1 ]] && ok "lib-syntax" "pilot/tasks/runlog OK"

runs_err=$(mktemp)
if [[ -f "$ROOT/runs.jsonl" ]]; then
  if node -e '
const fs = require("fs")
const lines = fs.readFileSync(process.argv[1], "utf8").split("\n").filter((l) => l.trim())
for (const l of lines) JSON.parse(l)
process.stdout.write(String(lines.length))
' "$ROOT/runs.jsonl" 2>"$runs_err" >/tmp/browser-runs-n.$$; then
    n=$(cat /tmp/browser-runs-n.$$ 2>/dev/null || echo 0)
    rm -f /tmp/browser-runs-n.$$
    ok "runs-jsonl" "$n filas validas"
  else
    fail "runs-jsonl" "$(tail -1 "$runs_err")"
  fi
else
  fail "runs-jsonl" "falta runs.jsonl"
fi
rm -f "$runs_err"

for pb in youtube x; do
  if [[ -s "$ROOT/playbooks/$pb.md" ]]; then
    ok "playbook:$pb" "playbooks/$pb.md"
  else
    fail "playbook:$pb" "falta o vacio playbooks/$pb.md"
  fi
done

exit "$rc"
