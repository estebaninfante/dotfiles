#!/usr/bin/env bash
set -uo pipefail

DOMAIN=agents
AGENTS_DIR="$HOME/.config/opencode/agents"
DESC_BUDGET=9000

rc=0
ok() { printf 'OK\t%s\t%s\n' "$1" "$2"; }
fail() { printf 'FAIL\t%s\t%s\n' "$1" "$2"; rc=1; }
skip() { printf 'SKIP\t%s\t%s\n' "$1" "$2"; }

audit=0
audit_days=7
for arg in "$@"; do
  case "$arg" in
    --probe)
      printf 'OK\tprobe\t%s\n' "$DOMAIN"
      exit 0
      ;;
    --audit-sessions)
      audit=1
      ;;
    --audit-sessions=*)
      audit=1
      audit_days="${arg#*=}"
      ;;
  esac
done
if [[ "${AGENTS_AUDIT:-0}" == "1" ]]; then
  audit=1
fi

if [[ ! -d "$AGENTS_DIR" ]]; then
  fail "agents-dir" "no existe $AGENTS_DIR"
  exit "$rc"
fi
ok "agents-dir" "$AGENTS_DIR"

policy_file="$HOME/.config/opencode/AGENTS.md"
if [[ -f "$policy_file" ]] \
   && grep -qF 'Verificacion proporcional al riesgo (E3)' "$policy_file" \
   && grep -qF 'Estimate -> Execute -> Expand' "$policy_file" \
   && grep -qF 'Anti-overcheck' "$policy_file" \
   && grep -qF 'Stop-and-ask' "$policy_file" \
   && grep -qF 'Escala por SEÑAL' "$policy_file"; then
  ok "policy-present" "AGENTS.md incluye la seccion E3 con sus reglas duras"
else
  fail "policy-present" "falta la seccion E3 (o alguna regla dura) en $policy_file"
fi

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

tier_err=$(mktemp)
AGENTS_DIR="$AGENTS_DIR" node -e '
const fs = require("fs")
const path = require("path")
const dir = process.env.AGENTS_DIR
const files = fs.readdirSync(dir).filter((f) => f.endsWith(".md") && !f.startsWith("cavecrew-")).sort()
const re = /Tier[^\n]*\b(micro|medio|riesgoso)\b/i
let bad = 0
for (const file of files) {
  const text = fs.readFileSync(path.join(dir, file), "utf8")
  if (!re.test(text)) {
    console.log("FAIL\tagents-declare-tier:" + file + "\tno declara Tier (E3) micro|medio|riesgoso")
    bad += 1
  }
}
if (bad === 0) console.log("OK\tagents-declare-tier\t" + files.length + " agentes declaran tier")
process.exit(bad ? 1 : 0)
' 2>"$tier_err"
tier_rc=$?
if [[ -s "$tier_err" ]]; then
  fail "agents-declare-tier" "$(tail -1 "$tier_err")"
elif [[ "$tier_rc" -ne 0 && "$tier_rc" -ne 1 ]]; then
  fail "agents-declare-tier" "node rc=$tier_rc"
fi
rm -f "$tier_err"
[[ "$tier_rc" -eq 0 ]] || rc=1

if [[ "$audit" -eq 1 ]]; then
  if [[ ! "$audit_days" =~ ^[0-9]+$ ]]; then
    fail "session-audit" "dias invalidos: $audit_days"
  else
    db="$HOME/.local/share/opencode/opencode.db"
    threshold="${AGENTS_AUDIT_TOOL_THRESHOLD:-60}"
    if [[ ! -f "$db" ]]; then
      skip "session-audit" "sin $db"
    elif ! command -v sqlite3 >/dev/null 2>&1; then
      skip "session-audit" "sqlite3 no disponible"
    else
      since_ms=$(( ($(date +%s) - audit_days * 86400) * 1000 ))
      rows=$(sqlite3 -separator $'\t' "$db" "
        select s.id, coalesce(s.agent, '?'), count(p.id)
        from session s join part p on p.session_id = s.id
        where json_extract(p.data, '\$.type') = 'tool' and s.time_created >= $since_ms
        group by s.id
        having count(p.id) > $threshold
        order by count(p.id) desc
        limit 25;" 2>/dev/null || true)
      micro_ids=$(sqlite3 "$db" "
        select distinct p.session_id from part p
        where json_extract(p.data, '\$.type') = 'text'
          and lower(json_extract(p.data, '\$.text')) like '%tier%micro%'
          and p.time_created >= $since_ms;" 2>/dev/null || true)
      if [[ -z "$rows" ]]; then
        ok "session-audit" "sin sesiones con >$threshold tool calls en $audit_days dias"
      else
        flagged=0
        while IFS=$'\t' read -r sid sagent scount; do
          [[ -z "$sid" ]] && continue
          if printf '%s\n' "$micro_ids" | grep -qxF "$sid"; then
            fail "session-audit" "$sid agente=$sagent tool_calls=$scount tier=micro excedido"
            flagged=1
          else
            printf 'OK\tsession-audit\t%s agente=%s tool_calls=%s sin tier micro declarado\n' "$sid" "$sagent" "$scount"
          fi
        done <<< "$rows"
        [[ "$flagged" -eq 1 ]] || ok "session-audit" "sin micro excedido en $audit_days dias"
      fi
    fi
  fi
else
  skip "session-audit" "opt-in: AGENTS_AUDIT=1 verify run agents (o agents.sh --audit-sessions)"
fi

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
