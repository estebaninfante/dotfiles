#!/usr/bin/env bash
set -uo pipefail

DOMAIN=rig
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_RIG="$SCRIPT_DIR/../../../../../bin/rig"
if [ -n "${RIG_SRC:-}" ]; then SRC="$RIG_SRC"
elif [ -f "$REPO_RIG" ]; then SRC="$(readlink -f "$REPO_RIG")"
else SRC="$HOME/dotfiles/linux/bin/rig"; fi
LINK="$HOME/.local/bin/rig"
STORE="$HOME/.config/opencode/tickets.json"
AREAS="hr hypr shell audio meta infra foldertinder"
export RIG_TICKETS_LOCK="${RIG_TICKETS_LOCK:-$(mktemp "${TMPDIR:-/tmp}/rig-verify-lock.XXXXXX")}"
export RIG_EVENTS_FILE="${RIG_EVENTS_FILE:-$(mktemp "${TMPDIR:-/tmp}/rig-verify-events.XXXXXX")}"

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
    *)
      targets+=("$arg")
      if [ "$(basename "$arg")" = "rig" ]; then SRC="$arg"; fi
      ;;
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

if command -v git >/dev/null 2>&1 && [ -d "$HOME/dotfiles/.git" ]; then
  if git -C "$HOME/dotfiles" ls-files --error-unmatch linux/bin/rig >/dev/null 2>&1; then
    ok "rig-tracked" "linux/bin/rig versionado en git (invariante: rig siempre trackeado)"
  else
    fail "rig-tracked" "linux/bin/rig NO esta trackeado por git: agregalo al repo (git add linux/bin/rig)"
  fi
else
  skip "rig-tracked" "sin repo git en ~/dotfiles"
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

if out=$("$SRC" spawn zz-probe --cwd /tmp --agent app-dev --prompt "hola mundo" --dry-run 2>&1); then
  if printf '%s' "$out" | grep -q -- '--model opencode/mimo-v2.6-flash-free'; then
    ok "seat-model" "spawn pasa --model explicito (default barato gratis, nivel 1)"
  else
    fail "seat-model" "spawn no fija el modelo barato: $out"
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
for fn in herdr_ensure_space herdr_attach_seat mirror_add; do
  grep -q "$fn" "$SRC" || hookok=0
done
if [ "$hookok" = "1" ]; then
  ok "herdr-hooks" "spawn engancha herdr (workspace/tab) + espejo tmux"
else
  fail "herdr-hooks" "rig sin herdr_ensure_space/herdr_attach_seat/mirror_add"
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

tabok=1
for fn in space_meta herdr_ensure_space window_label_for_seat herdr_kill_seats_in_space; do
  grep -q "$fn" "$SRC" || tabok=0
done
grep -q 'herdr workspace close' "$SRC" || tabok=0
createline=$(grep -m1 'workspace create' "$SRC")
case "$createline" in
  *"--label \"\$label\""*) : ;;
  *) tabok=0 ;;
esac
if [ "$tabok" = "1" ]; then
  ok "tabs-policy" "espacio por cosa: 1 unidad nueva = 1 workspace herdr (label #num/titulo o silla), cada agente su ventana; close cierra el space"
else
  fail "tabs-policy" "rig no sigue la politica de espacio-por-cosa (space_meta/herdr_ensure_space/window_label_for_seat/herdr_kill_seats_in_space)"
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
  badarea=$(jq -r --arg valid "$AREAS" '[.tickets[] | select(has("area")) | .area as $ar | select(($ar|type)!="string" or (($valid|split(" "))|index($ar)|not))]|length' "$STORE" 2>/dev/null || echo 999)
  if [ "${badarea:-999}" = "0" ]; then
    ok "tickets-area" "area valida o ausente"
  else
    fail "tickets-area" "${badarea} tickets con area invalida"
  fi
  badnum=$(jq -r '[.tickets[]|select((.num//0) <= 0 or (.num|type)!="number")]|length' "$STORE" 2>/dev/null || echo 999)
  if [ "${badnum:-999}" = "0" ]; then
    ok "tickets-num" "todo ticket tiene num secuencial"
  else
    fail "tickets-num" "${badnum} tickets sin num o con num invalido"
  fi
  badtitle=$(jq -r '[.tickets[]|select((.title|split(" ")|map(select(length>0))|length) < 6)]|length' "$STORE" 2>/dev/null || echo 999)
  if [ "${badtitle:-999}" = "0" ]; then
    ok "tickets-title" "titulos descriptivos (>= 6 palabras)"
  else
    fail "tickets-title" "${badtitle} titulos poco descriptivos (< 6 palabras)"
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
    if printf '%s' "$out" | jq -e 'all(has("area") and has("color") and has("num"))' >/dev/null 2>&1; then
      ok "board-porcelain" "JSON con area+color+num"
    else
      fail "board-porcelain" "faltan area/color en el porcelain"
    fi
  else
    fail "board-porcelain" "salida no es JSON array"
  fi
else
  fail "board-porcelain" "rig board --porcelain fallo: $(printf '%s' "$out" | head -n1)"
fi

if out=$(RIG_METRICS=0 "$SRC" board 2>&1); then
  if printf '%s' "$out" | grep -q 'total='; then
    ok "board-render" "render ok"
  else
    fail "board-render" "salida sin resumen"
  fi
else
  fail "board-render" "rig board fallo: $(printf '%s' "$out" | head -n1)"
fi

if out=$("$SRC" launch --help 2>&1); then
  if printf '%s' "$out" | grep -q 'rig launch' && printf '%s' "$out" | grep -q -- '--brief'; then
    ok "launch-help" "help de rig launch con --brief"
  else
    fail "launch-help" "help de launch sin --brief"
  fi
else
  fail "launch-help" "rig launch --help fallo"
fi

launchmiss=0
for fn in launch_deliver seat_ready launch_tokens_for_dir launch-failed; do
  grep -q "$fn" "$SRC" || launchmiss=1
done
if [ "$launchmiss" = "0" ]; then
  ok "launch-hooks" "entrega determinista presente (launch_deliver/seat_ready/launch-failed)"
else
  fail "launch-hooks" "faltan helpers de entrega en rig"
fi

if out=$("$SRC" scan --porcelain 2>&1); then
  if printf '%s' "$out" | jq -e '[.[]|select(.kind=="ticket")]|all(has("delivery"))' >/dev/null 2>&1; then
    ok "scan-delivery" "scan porcelain con campo delivery"
  else
    fail "scan-delivery" "scan porcelain sin campo delivery"
  fi
else
  fail "scan-delivery" "rig scan --porcelain fallo: $(printf '%s' "$out" | head -n1)"
fi

if out=$("$SRC" board --porcelain 2>&1); then
  if printf '%s' "$out" | jq -e 'all(has("delivery"))' >/dev/null 2>&1; then
    ok "board-delivery" "board porcelain con campo delivery"
  else
    fail "board-delivery" "board porcelain sin campo delivery"
  fi
else
  fail "board-delivery" "rig board --porcelain fallo: $(printf '%s' "$out" | head -n1)"
fi

if command -v tmux >/dev/null 2>&1; then
  lbtmp=$(mktemp); lbf=$(mktemp); lbev=$(mktemp)
  printf '{"version":1,"tickets":[]}\n' >"$lbtmp"
  printf 'encargo de prueba que no debe llegar nunca\n' >"$lbf"
  tmux kill-session -t zz-launch 2>/dev/null || true
  RIG_TICKETS_FILE="$lbtmp" RIG_METRICS=0 "$SRC" ticket add L1 --project meta --title "ticket de prueba de entrega fallida" --area meta >/dev/null 2>&1
  if RIG_TICKETS_FILE="$lbtmp" RIG_EVENTS_FILE="$lbev" RIG_METRICS=0 "$SRC" spawn zz-launch --cwd /tmp --cmd "sleep 600" --ticket L1 --brief "$lbf" --ready-timeout 2 --launch-retries 1 --no-herdr --no-mirror >/dev/null 2>&1; then
    fail "launch-failed-blocked" "spawn --brief con panel no listo debio fallar"
  else
    lbst=$(RIG_TICKETS_FILE="$lbtmp" "$SRC" ticket list --porcelain 2>/dev/null | jq -r '.[0].status' 2>/dev/null)
    if [ "$lbst" = "blocked" ] && grep -q 'launch-failed' "$lbev" 2>/dev/null; then
      ok "launch-failed-blocked" "entrega no confirmada -> blocked + evento launch-failed"
    else
      fail "launch-failed-blocked" "no dejo blocked/evento (status=${lbst:-?})"
    fi
  fi
  tmux kill-session -t zz-launch 2>/dev/null || true
  rm -f "$lbtmp" "$lbf" "$lbev"
else
  skip "launch-failed-blocked" "tmux no disponible"
fi

ftmp=$(mktemp)
printf '{"version":1,"tickets":[]}\n' >"$ftmp"
RIG_TICKETS_FILE="$ftmp" RIG_METRICS=0 "$SRC" ticket add SHOWT --project demo --title "ticket de prueba para la ficha de visibilidad" --area meta >/dev/null 2>&1

if out=$(RIG_TICKETS_FILE="$ftmp" RIG_METRICS=0 "$SRC" ticket show SHOWT 2>&1); then
  if printf '%s' "$out" | grep -q 'Que se hizo'; then
    ok "ticket-show-cli" "rig ticket show imprime la ficha"
  else
    fail "ticket-show-cli" "ficha sin seccion Que se hizo"
  fi
else
  fail "ticket-show-cli" "rig ticket show fallo: $(printf '%s' "$out" | head -n1)"
fi

if out=$(RIG_TICKETS_FILE="$ftmp" RIG_METRICS=0 "$SRC" ticket show SHOWT --porcelain 2>&1) && printf '%s' "$out" | jq -e '.id=="SHOWT"' >/dev/null 2>&1; then
  ok "ticket-show-porcelain" "JSON valido con el id del ticket"
else
  fail "ticket-show-porcelain" "salida no es JSON valido con .id"
fi

nowout=$(RIG_TICKETS_FILE="$ftmp" RIG_METRICS=0 "$SRC" ticket show SHOWT --no-metrics 2>&1 || true)
if [[ "$nowout" == *"no modifico nada"* ]]; then
  ok "ticket-show-noworktree" "sin worktree avisa que no modifico nada"
else
  fail "ticket-show-noworktree" "no avisa el estado sin worktree"
fi

if RIG_TICKETS_FILE="$ftmp" RIG_METRICS=0 "$SRC" board --detail >/dev/null 2>&1; then
  ok "board-detail" "board --detail no falla"
else
  fail "board-detail" "board --detail fallo"
fi

rm -f "$ftmp"

if grep -q 'ficha' "$SRC" && grep -q 'board --detail' "$SRC"; then
  ok "central-ficha" "central incluye el pane ficha"
else
  fail "central-ficha" "la central no arma el pane ficha"
fi

if grep -q 'notify_state_change' "$SRC" && grep -q 'RIG_STATE_NOTIFY' "$SRC"; then
  gtmp=$(mktemp -d)
  nbin="$gtmp/notify-send"
  printf '#!/bin/sh\necho "$*" >> %s\n' "$gtmp/log" >"$nbin"
  chmod +x "$nbin"
  stmp=$(mktemp)
  printf '{"version":1,"tickets":[]}\n' >"$stmp"
  RIG_TICKETS_FILE="$stmp" RIG_METRICS=0 "$SRC" ticket add NOT1 --project demo --title "ticket de prueba del aviso de estado" >/dev/null 2>&1
  RIG_TICKETS_FILE="$stmp" RIG_METRICS=0 RIG_NOTIFY_BIN="$nbin" "$SRC" ticket set NOT1 --status "done" >/dev/null 2>&1
  if [ -s "$gtmp/log" ]; then
    ok "state-notify" "el cambio a done dispara el aviso de escritorio"
  else
    fail "state-notify" "no disparo el aviso al cerrar el ticket"
  fi
  rm -rf "$gtmp" "$stmp"
else
  fail "state-notify" "la fuente no define notify_state_change/RIG_STATE_NOTIFY"
fi

if command -v sqlite3 >/dev/null 2>&1; then
  xtmp=$(mktemp -d)
  xdb="$xtmp/opencode.db"
  sqlite3 "$xdb" "CREATE TABLE session(id TEXT, title TEXT, directory TEXT, agent TEXT, model TEXT, cost REAL, tokens_input INTEGER, tokens_output INTEGER, tokens_reasoning INTEGER, tokens_cache_read INTEGER, tokens_cache_write INTEGER, time_created INTEGER, time_updated INTEGER);
    CREATE TABLE message(id TEXT, session_id TEXT, data TEXT);
    CREATE TABLE part(id TEXT, message_id TEXT, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT);
    INSERT INTO session VALUES('ses_x','t','/tmp','build','m',0.1,100,20,5,0,0,1000,2000);
    INSERT INTO message VALUES('msg_1','ses_x','{\"role\":\"user\"}');
    INSERT INTO part VALUES('prt_1','msg_1','ses_x',1500,1500,'{\"type\":\"text\",\"text\":\"hola\"}');" >/dev/null 2>&1

  if out=$(RIG_DB="$xdb" RIG_EXPORT_DIR="$xtmp/out" "$SRC" export ses_x 2>&1); then
    rpath=$(head -n1 <<<"$out")
    if [ -f "$rpath" ] && [ -s "$rpath" ]; then
      ok "export-cli" "rig export escribe el archivo y devuelve la ruta"
    else
      fail "export-cli" "no devolvio una ruta valida: $out"
    fi
  else
    fail "export-cli" "rig export fallo: $(head -n1 <<<"$out")"
  fi

  if out=$(RIG_DB="$xdb" RIG_EXPORT_DIR="$xtmp/out" "$SRC" export ses_x --format both --porcelain 2>&1) && jq -e '.kind=="session" and (.files|length>=1)' >/dev/null 2>&1 <<<"$out"; then
    ok "export-porcelain" "rig export --porcelain devuelve JSON con los archivos"
  else
    fail "export-porcelain" "salida no es JSON valido con files"
  fi
  rm -rf "$xtmp"
else
  skip "export-cli" "sqlite3 no disponible"
  skip "export-porcelain" "sqlite3 no disponible"
fi

atmp=$(mktemp)
printf '{"version":1,"tickets":[]}\n' >"$atmp"
if RIG_TICKETS_FILE="$atmp" RIG_METRICS=0 "$SRC" ticket add A-HR --project hypr-remote --title "ticket de prueba con area hr" --area hr >/dev/null 2>&1; then
  ok "area-add" "ticket add --area"
else
  fail "area-add" "ticket add --area fallo"
fi
if RIG_TICKETS_FILE="$atmp" RIG_METRICS=0 "$SRC" ticket add A-BAD --project x --title "titulo descriptivo de prueba" --area bogus >/dev/null 2>&1; then
  fail "area-valid" "area invalida fue aceptada"
else
  ok "area-valid" "area invalida rechazada"
fi
if RIG_TICKETS_FILE="$atmp" RIG_METRICS=0 "$SRC" ticket add A-SHORT --project x --title "muy corto" >/dev/null 2>&1; then
  fail "title-valid" "titulo corto fue aceptado"
else
  ok "title-valid" "titulo poco descriptivo rechazado"
fi
out=$(RIG_TICKETS_FILE="$atmp" RIG_METRICS=0 "$SRC" ticket --help 2>&1)
if printf '%s' "$out" | grep -q -- '--area' && printf '%s' "$out" | grep -q 'backfill'; then
  ok "area-cli" "rig ticket --help documenta --area/backfill"
else
  fail "area-cli" "rig ticket --help sin --area/backfill"
fi
colorok=1
for c in '#4C9AFF' '#B389FF' '#FFB84C' '#4CD9A0' '#8A8F98' '#FF7A85' '#7ADBFF'; do
  grep -q "$c" "$SRC" || colorok=0
done
if [ "$colorok" = "1" ]; then
  ok "area-color" "mapa de color completo en la fuente"
else
  fail "area-color" "falta algun color del mapa en $SRC"
fi
out=$(RIG_TICKETS_FILE="$atmp" RIG_METRICS=0 "$SRC" ticket list --porcelain 2>&1)
if printf '%s' "$out" | grep -q '"area": "hr"' && printf '%s' "$out" | grep -q '"color": "#4C9AFF"'; then
  ok "area-porcelain" "list --porcelain expone area+color"
else
  fail "area-porcelain" "list --porcelain sin area/color"
fi
out=$(RIG_TICKETS_FILE="$atmp" RIG_METRICS=0 "$SRC" board 2>&1)
if printf '%s' "$out" | grep -q 'hr'; then
  ok "board-area" "board agrupa por area (etiqueta hr)"
else
  fail "board-area" "board sin cabecera de area"
fi
out=$(RIG_TICKETS_FILE="$atmp" RIG_METRICS=0 "$SRC" board --plain 2>&1)
if [[ "$out" != *$'\033'* ]] && [[ "$out" == *"A-HR"* ]]; then
  ok "board-plain" "board --plain sin ANSI y con el ticket"
else
  fail "board-plain" "board --plain con ANSI o sin ticket"
fi
if RIG_TICKETS_FILE="$atmp" RIG_METRICS=0 "$SRC" ticket set 1 --evidence numericref >/dev/null 2>&1; then
  out=$(RIG_TICKETS_FILE="$atmp" RIG_METRICS=0 "$SRC" ticket list --porcelain 2>&1)
  if [[ "$out" == *'"num": 1'* ]] && [[ "$out" == *'"evidence": "numericref"'* ]]; then
    ok "num-resolve" "referencia numerica (#N o N) resuelve"
  else
    fail "num-resolve" "ref numerica no aplico al ticket"
  fi
else
  fail "num-resolve" "ticket set 1 (ref numerica) fallo"
fi
out=$(RIG_TICKETS_FILE="$atmp" RIG_METRICS=0 "$SRC" ticket list --porcelain 2>&1)
if printf '%s' "$out" | jq -e 'all((.num//0) > 0)' >/dev/null 2>&1; then
  ok "tickets-num" "todo ticket tiene num > 0"
else
  fail "tickets-num" "tickets sin num secuencial"
fi
rm -f "$atmp"

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

evtmp=$(mktemp -d)
evfile="$evtmp/events.jsonl"
if command -v jq >/dev/null 2>&1; then
  if out=$(RIG_EVENTS_FILE="$evfile" "$SRC" log "verifier evento uno" 2>&1) &&
     RIG_EVENTS_FILE="$evfile" "$SRC" log "verifier evento dos" >/dev/null 2>&1; then
    if [ "$(wc -l <"$evfile" 2>/dev/null | tr -d ' ')" = "2" ]; then
      ok "events-append" "dos logs -> dos lineas"
    else
      fail "events-append" "append no acumula lineas"
    fi
    if jq -e 'has("ts") and has("kind") and has("actor") and has("ticket") and has("seat") and has("area") and has("summary") and has("data")' "$evfile" >/dev/null 2>&1; then
      ok "events-shape" "eventos con los 8 campos"
    else
      fail "events-shape" "evento sin esquema completo"
    fi
    if out=$(RIG_EVENTS_FILE="$evfile" "$SRC" events --porcelain 2>&1) &&
       printf '%s\n' "$out" | jq -e -s 'length==2' >/dev/null 2>&1; then
      ok "events-porcelain" "--porcelain devuelve los eventos"
    else
      fail "events-porcelain" "events --porcelain no devuelve los eventos escritos"
    fi
  else
    fail "events-append" "rig log fallo: $(printf '%s' "$out" | head -n1)"
  fi
else
  skip "events-append" "jq ausente"
fi
if "$SRC" events --watch --porcelain >/dev/null 2>&1; then
  fail "events-watch-guard" "events --watch no debe combinarse con --porcelain"
else
  ok "events-watch-guard" "events --watch rechaza --porcelain"
fi
if out=$("$SRC" events --help 2>&1); then
  if printf '%s' "$out" | grep -q -- '--since' && printf '%s' "$out" | grep -q -- '--porcelain'; then
    ok "events-cli" "rig events documenta --since/--porcelain"
  else
    fail "events-cli" "rig events --help no documenta --since/--porcelain"
  fi
else
  fail "events-cli" "rig events --help fallo"
fi
if out=$("$SRC" log --help 2>&1); then
  if printf '%s' "$out" | grep -q -- '--ticket' && printf '%s' "$out" | grep -q -- '--seat'; then
    ok "log-cli" "rig log documenta --ticket/--seat"
  else
    fail "log-cli" "rig log --help no documenta --ticket/--seat"
  fi
else
  fail "log-cli" "rig log --help fallo"
fi
if grep -q 'cmd_events' "$SRC" && grep -q 'event_emit' "$SRC" && grep -q -- 'events --watch' "$SRC"; then
  ok "central-events" "central incluye el pane de eventos"
else
  fail "central-events" "central sin pane de eventos en vivo"
fi
if "$SRC" say --help >/dev/null 2>&1 && "$SRC" say --help 2>&1 | grep -q -- '--to' && "$SRC" say --help 2>&1 | grep -q 'reply'; then
  ok "say-cli" "rig say documenta --to y kind=reply"
else
  fail "say-cli" "rig say --help no documenta --to/reply"
fi
if "$SRC" say "x" --to bogus >/dev/null 2>&1; then
  fail "say-to-guard" "rig say acepta un --to invalido"
else
  ok "say-to-guard" "rig say rechaza --to invalido"
fi
if command -v jq >/dev/null 2>&1; then
  if RIG_EVENTS_FILE="$evfile" "$SRC" say "verifier respuesta al usuario" --to hub --ticket T13 >/dev/null 2>&1; then
    if RIG_EVENTS_FILE="$evfile" "$SRC" events --kind reply --since 10m --porcelain 2>/dev/null | jq -e 'select(.kind=="reply" and .actor=="main" and .data.to=="hub" and .summary=="verifier respuesta al usuario")' >/dev/null 2>&1; then
      ok "say-reply" "say deja un evento reply de main leible por --kind reply"
    else
      fail "say-reply" "el evento reply de main no aparece con --kind reply --since 10m --porcelain"
    fi
  else
    fail "say-reply" "rig say fallo"
  fi
else
  skip "say-reply" "jq no disponible"
fi
rm -rf "$evtmp"

if out=$("$SRC" ask --help 2>&1); then
  if printf '%s' "$out" | grep -q -- '--ticket' && printf '%s' "$out" | grep -q -- '--seat' \
     && printf '%s' "$out" | grep -q -- '--priority' && printf '%s' "$out" | grep -q 'kind=ask'; then
    ok "ask-cli" "rig ask documenta --ticket/--seat/--priority y el evento kind=ask"
  else
    fail "ask-cli" "rig ask --help no documenta --ticket/--seat/--priority/kind=ask"
  fi
else
  fail "ask-cli" "rig ask --help fallo"
fi

askbin=$(mktemp -d)
cat >"$askbin/rig-escalate" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_ASK_LOG"
exit 0
FAKE
chmod +x "$askbin/rig-escalate"
asklog="$askbin/ask.log"
: >"$asklog"
if RIG_ESCALATE_BIN="$askbin/rig-escalate" FAKE_ASK_LOG="$asklog" \
   "$SRC" ask "necesito una decision" --ticket T-1 --seat work-z --priority alta >/dev/null 2>&1; then
  if [ "$(cat "$asklog" 2>/dev/null)" = "necesito una decision --ticket T-1 --seat work-z --priority alta" ]; then
    ok "ask-delegates" "rig ask delega en rig-escalate con los args"
  else
    fail "ask-delegates" "rig ask no paso los args esperados: $(cat "$asklog" 2>/dev/null)"
  fi
else
  fail "ask-delegates" "rig ask fallo con RIG_ESCALATE_BIN fake"
fi
if "$SRC" ask "pregunta cualquiera" --priority bogus >/dev/null 2>&1; then
  fail "ask-priority-guard" "rig ask acepta --priority invalida"
else
  ok "ask-priority-guard" "rig ask rechaza --priority invalida"
fi
rm -rf "$askbin"

if "$SRC" scan --watch --porcelain >/dev/null 2>&1; then
  fail "scan-watch-guard" "scan --watch no debe combinarse con --porcelain"
else
  ok "scan-watch-guard" "scan --watch rechaza --porcelain"
fi
if grep -q 'scan_report' "$SRC" && out=$("$SRC" scan --help 2>&1); then
  if printf '%s' "$out" | grep -q -- '--watch'; then
    ok "scan-watch" "scan soporta modo vivo (--watch/scan_report)"
  else
    fail "scan-watch" "scan --help no documenta --watch"
  fi
else
  fail "scan-watch" "scan sin scan_report / --help"
fi

if out=$("$SRC" agents --help 2>&1); then
  if printf '%s' "$out" | grep -q 'working' && printf '%s' "$out" | grep -q 'derive'; then
    ok "agents-cli" "rig agents describe working|idle|blocked + fallback derive"
  else
    fail "agents-cli" "rig agents --help no describe estado/fallback"
  fi
else
  fail "agents-cli" "rig agents --help fallo"
fi
if command -v tmux >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  if out=$("$SRC" agents --porcelain 2>&1); then
    if printf '%s' "$out" | jq -e 'type=="array"' >/dev/null 2>&1; then
      ok "agents-porcelain" "JSON array valido"
    else
      fail "agents-porcelain" "salida no es JSON array"
    fi
  else
    fail "agents-porcelain" "rig agents --porcelain fallo: $(printf '%s' "$out" | head -n1)"
  fi
else
  skip "agents-porcelain" "tmux/jq no disponible"
fi

if out=$("$SRC" queue --help 2>&1); then
  if printf '%s' "$out" | grep -qi 'blocked'; then
    ok "queue-cli" "rig queue describe la cola pending/blocked"
  else
    fail "queue-cli" "rig queue --help no describe la cola"
  fi
else
  fail "queue-cli" "rig queue --help fallo"
fi
if command -v jq >/dev/null 2>&1; then
  if out=$("$SRC" queue --porcelain 2>&1); then
    if printf '%s' "$out" | jq -e 'has("pending") and has("blocked") and has("done")' >/dev/null 2>&1; then
      ok "queue-porcelain" "JSON valido (pending/blocked/done)"
    else
      fail "queue-porcelain" "salida sin pending/blocked/done"
    fi
  else
    fail "queue-porcelain" "rig queue --porcelain fallo: $(printf '%s' "$out" | head -n1)"
  fi
else
  skip "queue-porcelain" "jq no disponible"
fi

if grep -q 'cmd_central' "$SRC" && out=$("$SRC" central --help 2>&1); then
  if printf '%s' "$out" | grep -q 'CENTRAL' && printf '%s' "$out" | grep -q 'board'; then
    ok "central-cli" "rig central arma el workspace CENTRAL (board/scan/agents/queue)"
  else
    fail "central-cli" "rig central --help no describe los 4 panes"
  fi
else
  fail "central-cli" "rig central no disponible"
fi

idle_max="${RIG_IDLE_MAX_MIN:-60}"
[[ "$idle_max" =~ ^[0-9]+$ ]] || idle_max=60
if command -v jq >/dev/null 2>&1 && command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
  if out=$(RIG_IDLE_MAX_MIN="$idle_max" "$SRC" scan --porcelain --no-metrics 2>&1); then
    now=$(date +%s)
    stale=$(printf '%s' "$out" | jq -r --argjson now "$now" --argjson im "$idle_max" '
      [ .[] | select(.kind=="ticket") | select(.status=="in-progress")
        | select((.seat // "") != "") | select(.live == true) | select((.activity // 0) > 0)
        | select((($now - .activity) / 60) > $im)
        | "\(.id)=\((($now - .activity) / 60) | floor)min" ] | join(", ")' 2>/dev/null)
    if [ -z "$stale" ]; then
      ok "tickets-idle" "ninguna silla in-progress lleva mas de ${idle_max}min sin actividad"
    else
      skip "tickets-idle" "SENAL: sillas in-progress idle > ${idle_max}min: ${stale} (cierra el bucle: relanza o marca pending/blocked)"
    fi
  else
    skip "tickets-idle" "rig scan fallo"
  fi
else
  skip "tickets-idle" "tmux/jq no disponible"
fi

if out=$("$SRC" spaces --help 2>&1); then
  if printf '%s' "$out" | grep -q 'space' && printf '%s' "$out" | grep -qi 'reconcile' && printf '%s' "$out" | grep -qi 'usuario'; then
    ok "spaces-cli" "rig spaces documenta el mapeo ticket<->space y el cierre por el usuario"
  else
    fail "spaces-cli" "rig spaces --help no describe el mapeo/cierre por el usuario"
  fi
else
  fail "spaces-cli" "rig spaces --help fallo"
fi

lifeok2=1
grep -q 'seat_can_touch_ticket' "$SRC" || lifeok2=0
grep -q 'seat_owns_ticket' "$SRC" || lifeok2=0
grep -q 'store_unlock' "$SRC" || lifeok2=0
grep -q 'close_seat=0' "$SRC" || lifeok2=0
if [ "$lifeok2" = "1" ]; then
  ok "no-close-policy" "rig no cierra sillas/tickets ajenos y deja la silla/space vivos por defecto"
else
  fail "no-close-policy" "rig sin guard de propiedad (seat_can_touch_ticket/seat_owns_ticket) o sin default no-close"
fi

stateok=1
grep -q 'seat_agent_alive' "$SRC" || stateok=0
grep -q 'dead' "$SRC" || stateok=0
if "$SRC" agents --help 2>&1 | grep -q 'dead'; then :; else stateok=0; fi
if [ "$stateok" = "1" ]; then
  ok "state-fidelity" "rig agents detecta silla muerta/sin agente (estado dead) y no la deja en working"
else
  fail "state-fidelity" "rig agents no detecta silla muerta (seat_agent_alive/dead)"
fi

sptmp=$(mktemp -d)
printf '{"version":1,"tickets":[{"id":"SPT","project":"meta","title":"titulo de prueba para el space","status":"in-progress","owner":"x","created":"2026-10-13","updated":"2026-10-13","evidence":"","num":900,"space":"ws_gone"}]}' >"$sptmp/tickets.json"
mkdir -p "$sptmp/bin"
cat >"$sptmp/bin/herdr" <<'FAKEH'
#!/usr/bin/env bash
if [ "$1 $2" = "workspace list" ]; then printf '{"result":{"workspaces":[]}}'; exit 0; fi
exit 0
FAKEH
chmod +x "$sptmp/bin/herdr"
if PATH="$sptmp/bin:$PATH" RIG_HERDR=1 RIG_TICKETS_FILE="$sptmp/tickets.json" RIG_TICKETS_LOCK="$sptmp/lock" \
   RIG_EVENTS_FILE="$sptmp/events.jsonl" "$SRC" spaces reconcile >/dev/null 2>&1; then
  st=$(jq -r '.tickets[0].status' "$sptmp/tickets.json" 2>/dev/null)
  if [ "$st" = "done" ]; then
    ok "space-done-on-close" "space cerrado por el usuario marca el ticket done"
  else
    fail "space-done-on-close" "reconcile no marco done el ticket (status=$st)"
  fi
else
  fail "space-done-on-close" "rig spaces reconcile fallo con herdr simulado"
fi
rm -rf "$sptmp"

rm -f "$RIG_TICKETS_LOCK" "$RIG_EVENTS_FILE"
exit "$rc"
