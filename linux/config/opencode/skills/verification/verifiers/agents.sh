#!/usr/bin/env bash
set -uo pipefail

DOMAIN=agents
AGENTS_DIR="$HOME/.config/opencode/agents"
DESC_BUDGET=9000

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

if [[ ! -d "$AGENTS_DIR" ]]; then
  fail "agents-dir" "no existe $AGENTS_DIR"
  exit "$rc"
fi
ok "agents-dir" "$AGENTS_DIR"

spec_err=$(mktemp)
AGENTS_DIR="$AGENTS_DIR" DESC_BUDGET="$DESC_BUDGET" node -e '
const fs = require("fs")
const path = require("path")
const dir = process.env.AGENTS_DIR
const budget = Number(process.env.DESC_BUDGET)
const required = ["name", "description"]
const modes = ["all", "primary", "subagent"]
const files = fs.readdirSync(dir).filter((f) => f.endsWith(".md")).sort()
let bad = 0
let total = 0
for (const file of files) {
  const text = fs.readFileSync(path.join(dir, file), "utf8")
  const match = text.match(/^---\n([\s\S]*?)\n---/)
  if (!match) {
    console.log("FAIL\tspec:" + file + "\tfrontmatter ausente")
    bad += 1
    continue
  }
  const keys = {}
  let description = ""
  let mode = ""
  const lines = match[1].split("\n")
  let i = 0
  while (i < lines.length) {
    const keyMatch = lines[i].match(/^([A-Za-z_-]+)\s*:\s*(.*)$/)
    if (!keyMatch) {
      i += 1
      continue
    }
    keys[keyMatch[1]] = true
    let value = keyMatch[2]
    let j = i + 1
    while (j < lines.length && /^\s+\S/.test(lines[j])) {
      value += " " + lines[j].trim()
      j += 1
    }
    if (keyMatch[1] === "description") description = value
    if (keyMatch[1] === "mode") mode = value.trim()
    i = j
  }
  const body = text.slice(match[0].length).trim()
  const missing = required.filter((k) => !keys[k])
  if (missing.length) {
    console.log("FAIL\tspec:" + file + "\tfalta " + missing.join(","))
    bad += 1
    continue
  }
  if (!description.includes("Triggers:")) {
    console.log("FAIL\tspec:" + file + "\tdescription sin Triggers:")
    bad += 1
    continue
  }
  if (mode && !modes.includes(mode)) {
    console.log("FAIL\tspec:" + file + "\tmode invalido: " + mode)
    bad += 1
    continue
  }
  if (!body) {
    console.log("FAIL\tspec:" + file + "\tcuerpo vacio")
    bad += 1
    continue
  }
  total += description.length
}
if (bad === 0) console.log("OK\tspec\t" + files.length + " agentes validos")
if (total > budget) {
  console.log("FAIL\tdesc-budget\t" + total + " > " + budget + " chars en descripciones")
  process.exit(1)
}
console.log("OK\tdesc-budget\t" + total + " chars (max " + budget + ")")
process.exit(bad ? 1 : 0)
' 2>"$spec_err"
spec_rc=$?
if [[ -s "$spec_err" ]]; then
  fail "spec-node" "$(tail -1 "$spec_err")"
elif [[ "$spec_rc" -ne 0 && "$spec_rc" -ne 1 ]]; then
  fail "spec-node" "node rc=$spec_rc"
fi
rm -f "$spec_err"
[[ "$spec_rc" -eq 0 ]] || rc=1

newest=$(find "$AGENTS_DIR" -name '*.md' -printf '%T@\n' 2>/dev/null | sort -n | tail -1 | cut -d. -f1)
server_pid=""
p=$$
while [[ "$p" != "1" && -n "$p" ]]; do
  c=$(cat "/proc/$p/comm" 2>/dev/null || true)
  if [[ "$c" == "opencode" ]]; then
    server_pid="$p"
    break
  fi
  p=$(awk '{ for (i=1;i<=NF;i++) if ($i ~ /\)$/) { print $(i+2); exit } }' "/proc/$p/stat" 2>/dev/null)
done
if [[ -z "$server_pid" ]]; then
  skip "registry-fresh" "sin servidor opencode ancestro"
elif [[ -z "$newest" ]]; then
  skip "registry-fresh" "sin agentes"
else
  started=$(stat -c %Y "/proc/$server_pid" 2>/dev/null || echo 0)
  if [[ "$newest" -gt "$started" ]]; then
    fail "registry-fresh" "agente mas nuevo que el servidor pid $server_pid; reinicia opencode"
  else
    ok "registry-fresh" "servidor pid $server_pid incluye todos los agentes"
  fi
fi

exit "$rc"
