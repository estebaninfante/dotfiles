#!/usr/bin/env bash
set -uo pipefail

DOMAIN=agents
AGENTS_DIR="${AGENTS_DIR:-$HOME/.config/opencode/agents}"
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

policy_file="${AGENTS_POLICY_MD:-$HOME/.config/opencode/AGENTS.md}"
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

if [[ -f "$policy_file" ]] \
   && grep -qF 'unidades chicas + steering' "$policy_file" \
   && grep -qF 'session_interrupt' "$policy_file" \
   && grep -qF 'background=true' "$policy_file" \
   && grep -qF 'Delegar en unidades chicas' "$policy_file" \
   && grep -qF 'Volver al usuario entre unidades' "$policy_file"; then
  ok "interrupt-policy" "AGENTS.md define unidades chicas + steering + interrupcion"
else
  fail "interrupt-policy" "falta la politica de interrupcion/steering en $policy_file"
fi

if [[ -f "$policy_file" ]] \
   && grep -qF 'entrada/salida de UI se anima' "$policy_file" \
   && grep -qF 'ningun elemento aparece o desaparece abruptamente' "$policy_file" \
   && grep -qF 'fade/transicion' "$policy_file" \
   && grep -qF 'prefers-reduced-motion' "$policy_file"; then
  ok "motion-policy" "AGENTS.md exige fade/transicion en toda entrada/salida de UI"
else
  fail "motion-policy" "falta la regla de motion (nada abrupto) en $policy_file"
fi

if [[ -f "$policy_file" ]] \
   && grep -qF 'cambios paralelos con git worktree por ticket' "$policy_file" \
   && grep -qF 'un escritor por arbol' "$policy_file" \
   && grep -qF 'rig work' "$policy_file" \
   && grep -qF 'trazabilidad' "$policy_file"; then
  ok "worktree-policy" "AGENTS.md define cambios paralelos + trazabilidad por git worktree"
else
  fail "worktree-policy" "falta la politica de worktree por ticket en $policy_file"
fi

if [[ -f "$policy_file" ]] \
   && grep -qF 'Metricas por ticket' "$policy_file" \
   && grep -qF 'opencode.db' "$policy_file" \
   && grep -qF 'rig ticket metrics' "$policy_file" \
   && grep -qF 'ticket -> sesion' "$policy_file"; then
  ok "metrics-policy" "AGENTS.md define metricas por ticket (tokens/costo/tiempo)"
else
  fail "metrics-policy" "falta la politica de metricas por ticket en $policy_file"
fi

if [[ -f "$policy_file" ]] \
   && grep -qF 'Doctrina sillas-first' "$policy_file" \
   && grep -qF 'main es el punto de entrada y se mantiene libre' "$policy_file" \
   && grep -qF 'rig work new <ticket> --spawn' "$policy_file" \
   && grep -qF 'prohibido delegar con la tool' "$policy_file" \
   && grep -qF 'rig scan' "$policy_file"; then
  ok "sillas-policy" "AGENTS.md define la doctrina sillas-first (main libre, trabajo largo en sillas, task in-process prohibido)"
else
  fail "sillas-policy" "falta la doctrina sillas-first en $policy_file"
fi

if [[ -f "$policy_file" ]] \
   && grep -qF 'ningun pedido de trabajo queda sin lanzar' "$policy_file" \
   && grep -qF 'abre el ticket y la silla en el momento' "$policy_file" \
   && grep -qF 'Pregunta solo si hay bloqueo real' "$policy_file" \
   && grep -qF 'in-progress sin silla viva' "$policy_file"; then
  ok "launch-policy" "AGENTS.md exige lanzar (ticket+silla) cada pedido, sin dejarlo en '¿lo lanzo?'"
else
  fail "launch-policy" "falta la regla de lanzamiento inmediato (nada queda sin lanzar) en $policy_file"
fi

if [[ -f "$policy_file" ]] \
   && grep -qF 'ninguna silla se considera lanzada hasta que su encargo esta confirmado' "$policy_file" \
   && grep -qF 'rig launch' "$policy_file" \
   && grep -qF 'launch-failed' "$policy_file"; then
  ok "launch-confirm-policy" "AGENTS.md exige confirmar la entrega del encargo (rig launch/--brief, launch-failed)"
else
  fail "launch-confirm-policy" "falta la regla de entrega confirmada (ninguna silla lanzada sin encargo confirmado) en $policy_file"
fi

tickets_file="${RIG_TICKETS_FILE:-$HOME/.config/opencode/tickets.json}"
if [[ ! -f "$tickets_file" ]]; then
  skip "tickets-live" "sin $tickets_file"
elif ! command -v jq >/dev/null 2>&1 || ! command -v tmux >/dev/null 2>&1; then
  skip "tickets-live" "jq/tmux no disponible"
elif ! tmux list-sessions >/dev/null 2>&1; then
  skip "tickets-live" "sin servidor tmux"
else
  live_cwds="$(tmux list-sessions -F $'#{@agent}\t#{@agent_cwd}' 2>/dev/null | awk -F'\t' '$1=="1"{print $2}')"
  orphans="$(printf '%s\n' "$live_cwds" | jq -R -s -r --slurpfile tf "$tickets_file" '
    ($tf[0].tickets // []) as $tickets
    | (split("\n") | map(select(length > 0))) as $cwds
    | [ $tickets[]
        | select(.status == "in-progress")
        | (.worktree // "") as $w
        | select($w != "")
        | select(($cwds | index($w)) == null)
        | .id ]
    | .[]' 2>/dev/null)"
  if [[ -z "$orphans" ]]; then
    ok "tickets-live" "todo ticket in-progress con worktree tiene silla viva (seat en su worktree)"
  else
    fail "tickets-live" "in-progress con worktree sin silla viva: $(printf '%s' "$orphans" | paste -sd, -) (relanza: rig work new <id> --cwd <repo> --spawn, o marca pending/blocked)"
  fi
fi

main_file="$AGENTS_DIR/main.md"
if [[ -f "$main_file" ]] \
   && grep -qiE 'punto de entrada' "$main_file" \
   && grep -qiE 'prohibido' "$main_file" \
   && grep -qF 'task' "$main_file" \
   && grep -qiE 'silla' "$main_file"; then
  ok "main-pure" "main.md: punto de entrada puro, prohibe task in-process, delega en sillas"
else
  fail "main-pure" "main.md no declara punto de entrada puro / prohibicion de task in-process / delegacion por sillas"
fi

style_agents_md="${AGENTS_STYLE_MD:-$HOME/.config/opencode/AGENTS.md}"
style_main_md="${AGENTS_MAIN_MD:-$AGENTS_DIR/main.md}"
style_flag="${CAVEMAN_FLAG:-$HOME/.config/opencode/.caveman-active}"
style_cfg="${CAVEMAN_CFG:-$HOME/.config/caveman/config.json}"
style_reason=""
if [[ ! -f "$style_agents_md" ]] \
   || ! grep -qF 'Estilo de respuesta (REGLA DURA' "$style_agents_md" \
   || ! grep -qF 'espanol neutro' "$style_agents_md"; then
  style_reason="falta la regla de estilo en $style_agents_md"
elif [[ ! -f "$style_main_md" ]] \
   || ! grep -qF 'Estilo de respuesta (REGLA DURA' "$style_main_md" \
   || ! grep -qF 'espanol neutro' "$style_main_md"; then
  style_reason="falta la regla de estilo en $style_main_md"
elif [[ -f "$style_flag" ]]; then
  style_reason="flag caveman activo: $style_flag"
else
  style_mode="${CAVEMAN_DEFAULT_MODE:-}"
  if [[ -z "$style_mode" && -f "$style_cfg" ]]; then
    style_mode="$(node -e 'try{const c=require(process.argv[1]);process.stdout.write(String(c.defaultMode||"").toLowerCase())}catch(e){}' "$style_cfg" 2>/dev/null)"
  fi
  if [[ "$style_mode" != "off" ]]; then
    style_reason="caveman defaultMode=${style_mode:-ausente} != off (cfg $style_cfg)"
  fi
fi
if [[ -z "$style_reason" ]]; then
  ok "style-policy" "regla de estilo presente y caveman apagado por defecto (defaultMode=off, sin flag)"
else
  fail "style-policy" "$style_reason"
fi

if [[ -f "$policy_file" ]] \
   && grep -qF 'Politica de modelos por tipo de trabajo' "$policy_file" \
   && grep -qF 'Escalado por senal' "$policy_file" \
   && grep -qF 'opencode/mimo-v2.6-flash-free' "$policy_file" \
   && grep -qF 'opencode-go/deepseek-v4.1-flash' "$policy_file" \
   && grep -qF 'opencode-go/deepseek-v4-pro' "$policy_file"; then
  ok "model-policy" "AGENTS.md define la politica de modelos (3 niveles: gratis/flash/fuerte) + escalado por senal"
else
  fail "model-policy" "falta la politica de modelos de 3 niveles en $policy_file"
fi

appdev="$AGENTS_DIR/app-dev.md"
if [[ -f "$appdev" ]] \
   && grep -qiE 'implementacion de features' "$appdev" \
   && grep -qF 'app-architect' "$appdev" \
   && grep -qE '^model: *opencode/(mimo-v2\.6-flash-free|cat-jam-free)' "$appdev" \
   && grep -qiE 'Frontera' "$appdev" \
   && grep -qF 'Triggers:' "$appdev" \
   && grep -qF 'Implementacion de features (apps)' "$policy_file"; then
  ok "app-dev-owner" "app-dev existe: owner de implementacion, modelo gratuito, frontera con app-architect, fila en AGENTS.md"
else
  fail "app-dev-owner" "app-dev falta o no cumple (owner implementacion + modelo gratis + frontera + Triggers + fila en AGENTS.md)"
fi

models_list=""
if command -v opencode >/dev/null 2>&1; then
  models_list="$(opencode models 2>/dev/null | awk '{print $1}')"
fi
if [[ -z "$models_list" ]]; then
  skip "model-valid" "opencode models no disponible"
else
  bad_models=""
  for f in "$AGENTS_DIR"/*.md; do
    [[ -e "$f" ]] || continue
    m="$(awk -F':[[:space:]]*' '/^model:/{print $2; exit}' "$f" | tr -d '[:space:]')"
    [[ -z "$m" ]] && continue
    printf '%s\n' "$models_list" | grep -qxF "$m" || bad_models="$bad_models $(basename "$f"):$m"
  done
  if [[ -z "$bad_models" ]]; then
    ok "model-valid" "todo model: de agente existe en opencode models"
  else
    fail "model-valid" "model invalido (no esta en opencode models):$bad_models"
  fi
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

herdr_plugin="${HERDR_REPORTER:-$HOME/.config/opencode/plugins/herdr-pane-state.js}"
if [[ ! -f "$herdr_plugin" ]]; then
  fail "herdr-reporter" "falta $herdr_plugin (el panel nativo de herdr no se pobla con opencode >=1.19)"
else
  herdr_problem=$(node --no-warnings --input-type=module -e '
const file = process.argv[1]
import("file://" + file)
  .then((mod) => {
    if (typeof mod.default === "function") console.log("")
    else console.log("default export no es funcion: usa la API V1 y no reporta en opencode 1.19")
  })
  .catch((error) => console.log("no carga: " + String((error && error.message) || error)))
' "$herdr_plugin" 2>/dev/null)
  if [[ -n "$herdr_problem" ]]; then
    fail "herdr-reporter" "$herdr_problem"
  elif ! grep -qF 'pane.report_agent' "$herdr_plugin" || ! grep -qF 'HERDR_PANE_ID' "$herdr_plugin" || ! grep -qF 'HERDR_ENV' "$herdr_plugin"; then
    fail "herdr-reporter" "no reporta pane.report_agent con guard HERDR_ENV/HERDR_PANE_ID"
  else
    ok "herdr-reporter" "plugin V2-style presente y reporta estado al socket de herdr"
  fi
fi

herdr_managed="${HERDR_MANAGED_PLUGIN:-$HOME/.config/opencode/plugins/herdr-agent-state.js}"
if [[ ! -f "$herdr_managed" ]]; then
  skip "herdr-single-source" "sin plugin gestionado por herdr en $herdr_managed"
else
  managed_export=$(node --input-type=module -e '
import(process.argv[1])
  .then((mod) => console.log(typeof mod.default === "function" ? "function" : "object"))
  .catch(() => console.log("error"))
' "file://$herdr_managed" 2>/dev/null)
  if [[ "$managed_export" == "function" ]]; then
    fail "herdr-single-source" "el plugin gestionado por herdr reporta (V2): dos fuentes sobre el mismo pane; desactiva una"
  else
    ok "herdr-single-source" "una sola fuente activa (el gestionado por herdr es V1 inerte en opencode >=1.19)"
  fi
fi

exit "$rc"
