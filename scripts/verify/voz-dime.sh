#!/usr/bin/env bash
# verify/voz-dime.sh — la campana y "dime": los mensajes no se hablan solos.
#
# Síntoma que protege: cada mensaje de un agente se hablaba al llegar (o con un
# híbrido que igual interrumpía). Ahora la entrega por defecto es `bell`: suena
# una campana (una vez por ráfaga) y el mensaje queda en el buzón. Recién cuando
# decís "dime" (o `voice dime`) Omar lee la cola: "<agente> dice: <mensaje>".
#
# Solo lee el repo y usa un historial temporal: no habla, no necesita daemon ni
# micrófono.
#
# Uso:
#   scripts/verify/voz-dime.sh          # texto
#   scripts/verify/voz-dime.sh --quiet  # solo FALLA
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$REPO/linux/bin/voice"
ENGINE="$REPO/linux/voice/engine.py"
CONFIG="$REPO/linux/config/voice/config.toml"
README="$REPO/linux/voice/README.md"
HOTWORDS="${OMAR_HOTWORDS:-$HOME/.local/share/omar/hotwords.json}"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

[ -f "$CLI" ]    || { echo "no encuentro $CLI" >&2; exit 1; }
[ -f "$ENGINE" ] || { echo "no encuentro $ENGINE" >&2; exit 1; }

# --- 1. la entrega por defecto no habla --------------------------------
if rg -q '^delivery = "bell"' "$CONFIG"; then
  ok "entrega por defecto: bell"
else
  fail "la entrega por defecto no es bell"
fi
if awk '/bell\|mailbox\)/{f=1} f&&/record-message/{r=1} f&&/--pending/{p=1} f&&/;;/{exit} END{exit !(r&&p)}' "$CLI"; then
  ok "bell acumula en el buzón (no habla)"
else
  fail "bell no acumula en el buzón"
fi

# --- 2. la campana respeta el dictado y no repite ----------------------
if awk '/^chime\(\)/{f=1} f&&/chime.last/{d=1} f&&/wait_mic_free/{w=1} f&&/^}/{exit} END{exit !(d&&w)}' "$CLI"; then
  ok "campana: debounce + espera al dictado"
else
  fail "campana sin debounce o sin esperar al dictado"
fi

# --- 3. "dime" lee la cola en orden, con autor y tope ------------------
if rg -q '^\s*dime\) shift; dime ' "$CLI"; then
  ok "comando dime"
else
  fail "falta el comando dime"
fi
if rg -q '"\$fuente dice: \$texto"' "$CLI"; then
  ok "formato \"<agente> dice: <mensaje>\""
else
  fail "formato de lectura incorrecto"
fi
if rg -q 'Quedan \$restan mensajes' "$CLI" && rg -q 'pending-count' "$CLI"; then
  ok "tope por lectura y aviso de los que quedan"
else
  fail "no avisa cuántos quedan"
fi
if rg -q 'dime_max_age_min' "$CLI" && rg -q 'prune-pending' "$CLI" \
   && rg -q 'dime_keep' "$CLI"; then
  ok "buffer: TTL por edad + tope de guardado"
else
  fail "sin TTL/tope de guardado"
fi
if rg -q 'dime_max_recent' "$CLI" && rg -q 'dime_fresh_min' "$CLI"; then
  ok "tope alto si todo es reciente"
else
  fail "sin tope alto para mensajes recientes"
fi
if rg -q 'mark-heard --id' "$CLI"; then
  ok "marca escuchado por id (no por hora)"
else
  fail "sigue marcando por ts"
fi
if rg -q 'quiet-empty' "$CLI"; then
  ok "modo silencioso si no hay nada (hotword)"
else
  fail "sin modo silencioso para la hotword"
fi
if rg -q 'bell' "$README"; then
  ok "documentado en el README de voz"
else
  fail "sin documentar en el README"
fi

# --- 4. la hotword "dime" está instalada ------------------------------
if [ -f "$HOTWORDS" ] && python3 - "$HOTWORDS" <<'PY'
import json, sys
reglas = json.load(open(sys.argv[1]))
for r in reglas:
    if r.get("id") == "dime":
        acciones = r.get("actions") or []
        if any("voice dime" in str(a.get("command", "")) for a in acciones):
            sys.exit(0)
sys.exit(1)
PY
then
  ok "hotword \"dime\" -> voice dime"
else
  fail "falta la hotword dime"
fi

# --- 5. el buzón de verdad: alta, orden y lectura ---------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export VOICE_HISTORY_DIR="$tmp/tts"
mkdir -p "$VOICE_HISTORY_DIR"
python3 "$ENGINE" record-message --source pi   --text "primero" --pending >/dev/null
python3 "$ENGINE" record-message --source omar --text "segundo" --pending >/dev/null
if [ "$(python3 "$ENGINE" pending-count)" = "2" ]; then
  ok "el buzón acumula 2 pendientes"
else
  fail "el buzón no acumula"
fi
orden="$(python3 "$ENGINE" pending 2>/dev/null | awk '{print $NF}' | tr '\n' ' ')"
if [ "$orden" = "primero segundo " ]; then
  ok "lectura en orden (más viejo primero)"
else
  fail "orden de lectura: $orden"
fi
# marcar por id: dos mensajes en el mismo ms no se llevan de a dos
python3 "$ENGINE" record-message --source pi --text "tercero" --pending >/dev/null
python3 - <<'PYEOF'
import json, os, time
p = os.path.join(os.environ["VOICE_HISTORY_DIR"], "messages.jsonl")
l = [json.loads(x) for x in open(p) if x.strip()]
ts = int(time.time() * 1000)
for r in l:
    r["ts"] = ts  # todos el mismo milisegundo
open(p, "w").write("\n".join(json.dumps(r, ensure_ascii=False) for r in l) + "\n")
PYEOF
ident="$(python3 "$ENGINE" pending --json 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)[0]["id"])')"
python3 "$ENGINE" mark-heard --id "$ident" >/dev/null
if [ "$(python3 "$ENGINE" pending-count)" = "2" ]; then
  ok "marcar por id sólo se lleva uno (aunque compartan hora)"
else
  fail "marcar por id se llevó de más"
fi

# TTL: lo viejo se descarta y no se lee
python3 - <<'PYEOF'
import json, os, time
p = os.path.join(os.environ["VOICE_HISTORY_DIR"], "messages.jsonl")
l = [json.loads(x) for x in open(p) if x.strip()]
for r in l:
    r["ts"] = int(time.time() * 1000) - 90 * 60 * 1000
open(p, "w").write("\n".join(json.dumps(r, ensure_ascii=False) for r in l) + "\n")
PYEOF
python3 "$ENGINE" prune-pending --max-age-min 30 --keep 20 >/dev/null
if [ "$(python3 "$ENGINE" pending-count)" = "0" ]; then
  ok "lo de hace 90 min se descarta solo"
else
  fail "no descarta los mensajes viejos"
fi
if rg -q '"expired": true' "$VOICE_HISTORY_DIR/messages.jsonl"; then
  ok "queda marcado como expirado (no se borra del historial)"
else
  fail "no marca expired"
fi

# tope de guardado: el buffer tira los más viejos
for i in $(seq 1 5); do python3 "$ENGINE" record-message --source pi --text "b$i" --pending >/dev/null; done
n="$(python3 "$ENGINE" prune-pending --max-age-min 30 --keep 3)"
if [ "$n" = "2" ] && [ "$(python3 "$ENGINE" pending-count)" = "3" ]; then
  ok "el buffer tira los más viejos al llegar al tope"
else
  fail "el tope del buffer no funciona (descartó $n)"
fi

if [ "$fails" -eq 0 ]; then
  [ "$QUIET" = 1 ] || printf '\nvoz-dime: todo ok\n'
  exit 0
fi
printf '\nvoz-dime: %d falla(s)\n' "$fails" >&2
exit 1
