#!/usr/bin/env bash
set -uo pipefail

DOMAIN=rig
SRC="$HOME/dotfiles/linux/bin/rig"
LINK="$HOME/.local/bin/rig"
STORE="$HOME/.config/opencode/tickets.json"

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

if [ ${#targets[@]} -eq 0 ]; then
  targets=("$SRC")
fi

for target in "${targets[@]}"; do
  base=$(basename "$target")
  case "$target" in
    *.sh|*/rig) ;;
    *)
      skip "syntax:$base" "no es script bash"
      continue
      ;;
  esac
  if bash -n "$target" 2>/dev/null; then
    ok "syntax:$base" "bash -n"
  else
    fail "syntax:$base" "$(bash -n "$target" 2>&1 | head -n1)"
  fi
  if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$target" >/dev/null 2>&1; then
      ok "shellcheck:$base" "limpio"
    else
      fail "shellcheck:$base" "$(shellcheck "$target" 2>&1 | head -n2 | tr '\n' ' ')"
    fi
  else
    skip "shellcheck:$base" "shellcheck no instalado"
  fi
done

if [ -x "$SRC" ]; then
  if out=$("$SRC" --selftest 2>&1); then
    ok "selftest" "$(printf '%s' "$out" | tail -n1)"
  else
    fail "selftest" "$(printf '%s' "$out" | tail -n1)"
  fi
else
  fail "selftest" "$SRC no ejecutable"
fi

if [ -L "$LINK" ]; then
  if [ -x "$(readlink -f "$LINK")" ]; then
    ok "symlink" "$LINK -> $(readlink "$LINK")"
  else
    fail "symlink" "$LINK apunta a archivo inexistente"
  fi
else
  fail "symlink" "$LINK no existe"
fi

if command -v jq >/dev/null 2>&1; then
  ok "jq" "$(jq --version)"
else
  skip "jq" "jq no instalado (store de tickets)"
fi

if command -v git >/dev/null 2>&1; then
  ok "git" "$(git --version)"
else
  fail "git" "git no instalado (requerido por rig work)"
fi

if out=$("$SRC" work --help 2>&1); then
  if printf '%s' "$out" | grep -q 'worktree'; then
    ok "work-cli" "rig work disponible"
  else
    fail "work-cli" "rig work --help no menciona worktree"
  fi
else
  fail "work-cli" "rig work --help fallo"
fi

if out=$("$SRC" spawn zz-probe --cwd /tmp --agent app-architect --prompt "hola mundo" --dry-run 2>&1); then
  first=${out%% *}
  flagok=1
  printf '%s' "$out" | grep -q -- '--agent app-architect' || flagok=0
  printf '%s' "$out" | grep -q -- '--prompt' || flagok=0
  printf '%s' "$out" | grep -Eq 'mise x|/opencode' || flagok=0
  case "$first" in opencode) flagok=0 ;; esac
  if [ "$flagok" = "1" ]; then
    ok "spawn-agent-flag" "usa binario real (no alias): $first"
  else
    fail "spawn-agent-flag" "comando no resuelve el binario o pierde --agent/--prompt: $out"
  fi
else
  fail "spawn-agent-flag" "rig spawn --dry-run fallo: $(printf '%s' "$out" | head -n1)"
fi

if out=$("$SRC" spawn zz-probe --cwd /tmp --cmd "opencode --agent app-architect" --dry-run 2>&1); then
  first=${out%% *}
  case "$first" in
    opencode) fail "spawn-cmd-harden" "custom 'opencode' quedo con el alias/wrapper: $out" ;;
    *)
      if printf '%s' "$out" | grep -Eq 'mise x|/opencode'; then
        ok "spawn-cmd-harden" "--cmd con 'opencode' usa el binario real"
      else
        fail "spawn-cmd-harden" "no se endurecio el custom: $out"
      fi
      ;;
  esac
else
  fail "spawn-cmd-harden" "rig spawn --cmd --dry-run fallo: $(printf '%s' "$out" | head -n1)"
fi

if out=$("$SRC" spawn zz-probe --cwd /tmp --agent app-architect --prompt "hola mundo" --dry-run 2>&1); then
  if printf '%s' "$out" | grep -q -- '--model opencode-go/deepseek-v4.1-flash'; then
    ok "seat-model" "spawn pasa --model explicito (default deepseek-v4.1-flash)"
  else
    fail "seat-model" "spawn no fija --model: $out"
  fi
else
  fail "seat-model" "rig spawn --dry-run fallo: $(printf '%s' "$out" | head -n1)"
fi

if out=$(RIG_SEAT_MODEL=zz/model "$SRC" spawn zz-probe --cwd /tmp --dry-run 2>&1); then
  if printf '%s' "$out" | grep -q -- '--model zz/model'; then
    ok "seat-model-env" "RIG_SEAT_MODEL override respetado"
  else
    fail "seat-model-env" "RIG_SEAT_MODEL ignorado: $out"
  fi
else
  fail "seat-model-env" "rig spawn --dry-run fallo con env"
fi

hookok=1
for fn in herdr_ensure_ws herdr_attach_seat mirror_add; do
  grep -q "$fn" "$SRC" || hookok=0
done
if [ "$hookok" = "1" ]; then
  ok "herdr-hooks" "spawn engancha herdr (workspace/tab) + espejo tmux"
else
  fail "herdr-hooks" "rig sin herdr_ensure_ws/herdr_attach_seat/mirror_add"
fi

if grep -q 'herdr_focus_seat' "$SRC" && "$SRC" --help 2>&1 | grep -q -- '--no-focus'; then
  ok "herdr-focus" "spawn enfoca el tab herdr por defecto (--no-focus lo desactiva)"
else
  fail "herdr-focus" "spawn no enfoca herdr (falta herdr_focus_seat / --no-focus en la ayuda)"
fi

lifeok=1
grep -q 'close_seat_for_ticket' "$SRC" || lifeok=0
"$SRC" --help 2>&1 | grep -q -- '--close-seat' || lifeok=0
if [ "$lifeok" = "1" ]; then
  ok "lifecycle-cli" "work finish/ticket done cierran la silla (--close-seat)"
else
  fail "lifecycle-cli" "rig sin ciclo de vida de silla (close_seat_for_ticket / --close-seat)"
fi

synok=1
grep -q 'herdr_sync_seat' "$SRC" || synok=0
grep -q 'cmd_herdr' "$SRC" || synok=0
"$SRC" --help 2>&1 | grep -q 'herdr sync' || synok=0
grep -q 'HERDR_PANE_ID=' "$SRC" || synok=0
if [ "$synok" = "1" ]; then
  ok "herdr-sync-cli" "spawn inyecta HERDR_* en la silla y 'rig herdr sync' registra el estado"
else
  fail "herdr-sync-cli" "rig sin env-injection herdr o sin 'rig herdr sync'"
fi

if command -v sqlite3 >/dev/null 2>&1; then
  ok "sqlite3" "$(sqlite3 --version | awk '{print $1}')"
else
  skip "sqlite3" "sqlite3 no instalado (metricas por ticket)"
fi

if out=$("$SRC" ticket --help 2>&1); then
  if printf '%s' "$out" | grep -q 'metrics'; then
    ok "metrics-cli" "rig ticket metrics disponible"
  else
    fail "metrics-cli" "rig ticket --help no menciona metrics"
  fi
else
  fail "metrics-cli" "rig ticket --help fallo"
fi

DB_FILE="$HOME/.local/share/opencode/opencode.db"
if [ -f "$DB_FILE" ] && command -v sqlite3 >/dev/null 2>&1; then
  cols=$(sqlite3 -readonly "$DB_FILE" "SELECT group_concat(name) FROM pragma_table_info('session')" 2>/dev/null)
  if printf '%s' "$cols" | grep -q 'parent_id' && printf '%s' "$cols" | grep -q 'cost' \
    && printf '%s' "$cols" | grep -q 'tokens_input' && printf '%s' "$cols" | grep -q 'time_created'; then
    ok "db-schema" "session tiene parent_id/cost/tokens/time"
  else
    fail "db-schema" "session sin columnas esperadas: ${cols:-<none>}"
  fi
else
  skip "db-schema" "sin $DB_FILE o sin sqlite3"
fi

if [ -f "$STORE" ]; then
  if jq -e '.tickets|type=="array"' "$STORE" >/dev/null 2>&1; then
    ok "tickets-store" "JSON valido"
  else
    fail "tickets-store" "$STORE invalido"
  fi
  badshape=$(jq -r '[.tickets[]|select((.id|type!="string") or (.project|type!="string") or (.title|type!="string") or (.status|type!="string") or (.owner|type!="string") or (.created|type!="string") or (.updated|type!="string") or (.evidence|type!="string"))]|length' "$STORE" 2>/dev/null || echo 999)
  if [ "${badshape:-999}" = "0" ]; then
    ok "tickets-shape" "campos completos"
  else
    fail "tickets-shape" "${badshape} tickets con campos faltantes o tipo invalido"
  fi
  badstatus=$(jq -r '[.tickets[]|select(.status|IN("pending","in-progress","blocked","done")|not)]|length' "$STORE" 2>/dev/null || echo 999)
  if [ "${badstatus:-999}" = "0" ]; then
    ok "tickets-status" "estados validos"
  else
    fail "tickets-status" "${badstatus} tickets con estado invalido"
  fi
  dupes=$(jq -r '[.tickets[].id]|group_by(.)|map(select(length>1))|length' "$STORE" 2>/dev/null || echo 999)
  if [ "${dupes:-999}" = "0" ]; then
    ok "tickets-unique" "ids unicos"
  else
    fail "tickets-unique" "${dupes} ids duplicados"
  fi
  badwork=$(jq -r '[.tickets[]|select((has("branch") and (.branch|type!="string")) or (has("worktree") and (.worktree|type!="string")) or (has("repo") and (.repo|type!="string")) or (has("base") and (.base|type!="string")) or (has("commits") and (.commits|type!="string")))]|length' "$STORE" 2>/dev/null || echo 999)
  if [ "${badwork:-999}" = "0" ]; then
    ok "tickets-work-shape" "campos de worktree validos"
  else
    fail "tickets-work-shape" "${badwork} tickets con campos de worktree invalidos"
  fi
  badlink=$(jq -r '[.tickets[]|select((.worktree//"")!="" and (.branch//"")=="")]|length' "$STORE" 2>/dev/null || echo 999)
  if [ "${badlink:-999}" = "0" ]; then
    ok "worktree-link" "todo worktree tiene branch"
  else
    fail "worktree-link" "${badlink} tickets con worktree sin branch"
  fi
  badsess=$(jq -r '[.tickets[]|select(has("sessions") and ((.sessions|type!="array") or ([.sessions[]|select(type!="string")]|length>0)))]|length' "$STORE" 2>/dev/null || echo 999)
  if [ "${badsess:-999}" = "0" ]; then
    ok "tickets-sessions-shape" "sessions es array de strings"
  else
    fail "tickets-sessions-shape" "${badsess} tickets con sessions invalido"
  fi
else
  skip "tickets-store" "no existe $STORE"
fi

if out=$("$SRC" board --porcelain 2>&1); then
  if printf '%s' "$out" | jq -e 'type=="array"' >/dev/null 2>&1; then
    ok "board-porcelain" "JSON valido"
  else
    fail "board-porcelain" "salida no es JSON array"
  fi
else
  fail "board-porcelain" "rig board --porcelain fallo: $(printf '%s' "$out" | head -n1)"
fi

if out=$("$SRC" board 2>&1); then
  if printf '%s' "$out" | grep -q 'total='; then
    ok "board-render" "render ok"
  else
    fail "board-render" "salida sin resumen"
  fi
else
  fail "board-render" "rig board fallo: $(printf '%s' "$out" | head -n1)"
fi

if out=$("$SRC" scan --help 2>&1); then
  if printf '%s' "$out" | grep -q 'worktree' && printf '%s' "$out" | grep -q 'archivos modificados'; then
    ok "scan-cli" "rig scan disponible"
  else
    fail "scan-cli" "rig scan --help no describe worktree/archivos"
  fi
else
  fail "scan-cli" "rig scan --help fallo"
fi

if out=$("$SRC" scan --porcelain 2>&1); then
  if printf '%s' "$out" | jq -e 'type=="array"' >/dev/null 2>&1; then
    ok "scan-porcelain" "JSON valido"
  else
    fail "scan-porcelain" "salida no es JSON array"
  fi
else
  fail "scan-porcelain" "rig scan --porcelain fallo: $(printf '%s' "$out" | head -n1)"
fi

etmp=$(mktemp)
printf '{"version":1,"tickets":[]}\n' >"$etmp"
if out=$(RIG_TICKETS_FILE="$etmp" "$SRC" scan --porcelain --no-seats 2>&1); then
  if [ "$(printf '%s' "$out" | tr -d '[:space:]')" = "[]" ]; then
    ok "scan-empty" "empty state devuelve []"
  else
    fail "scan-empty" "scan vacio no devuelve []: $(printf '%s' "$out" | head -n1)"
  fi
else
  fail "scan-empty" "rig scan --no-seats fallo: $(printf '%s' "$out" | head -n1)"
fi
if out=$(RIG_TICKETS_FILE="$etmp" "$SRC" scan --no-seats 2>&1); then
  if printf '%s' "$out" | grep -q 'no hay sillas ni worktrees activos'; then
    ok "scan-empty-render" "render avisa el empty state"
  else
    fail "scan-empty-render" "render sin empty state honesto"
  fi
else
  fail "scan-empty-render" "rig scan vacio fallo"
fi
rm -f "$etmp"

exit "$rc"
