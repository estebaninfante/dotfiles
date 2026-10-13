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

tabok=1
for fn in tab_label_for_seat herdr_tab_for_label herdr_split_pane herdr_kill_seats_on_tab; do
  grep -q "$fn" "$SRC" || tabok=0
done
grep -q 'herdr tab close' "$SRC" || tabok=0
createline=$(grep -m1 'tab create' "$SRC")
case "$createline" in
  *"--label \"\$label\""*) : ;;
  *) tabok=0 ;;
esac
if [ "$tabok" = "1" ]; then
  ok "tabs-policy" "herdr tab = ticket; 2do agente -> pane split; sin ticket -> tab = silla"
else
  fail "tabs-policy" "rig no sigue la politica de tabs por ticket (tab_label_for_seat/herdr_tab_for_label/herdr_split_pane/kill-seats)"
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

exit "$rc"
