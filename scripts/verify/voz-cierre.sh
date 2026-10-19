#!/usr/bin/env bash
# verify/voz-cierre.sh — el cierre hablado no suena si el usuario interrumpió.
#
# Solo lee; no cambia nada. Sale 0 si:
#   - las reglas puras de lib/tts-cierre.ts pasan sus casos con Node;
#   - la extensión está instalada (symlink) y usa esas reglas;
#   - el respaldo que lee la sesión no puede resucitar texto de turnos viejos;
#   - el cierre en vuelo se descarta si el usuario corta mientras se genera.
#
# La prueba de punta a punta (correr un turno, cortar otro y mirar que el TTS
# no diga nada) se hace a mano con `PI_TTS_DRY=1`:
#   PI_TTS_DRY=1 PI_TTS_DRY_FILE=/tmp/tts.txt pi --mode rpc
#   ... prompt largo, `{"type":"abort"}` ... y /tmp/tts.txt no debe crecer.
#
# Uso:
#   scripts/verify/voz-cierre.sh          # texto
#   scripts/verify/voz-cierre.sh --quiet  # solo FALLA
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXTS="$REPO/linux/pi/agent/extensions"
HELPERS="$EXTS/lib/tts-cierre.ts"
TESTS="$EXTS/lib/tts-cierre.test.ts"
EXT="$EXTS/tts-summary.ts"
INSTALADA="${HOME}/.pi/agent/extensions/tts-summary.ts"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

# --- 1. reglas puras: corren solas con Node -------------------------------
if out="$(node --test "$TESTS" 2>&1)"; then
    ok "casos de lib/tts-cierre.ts"
else
    fail "casos de lib/tts-cierre.ts"
    printf '%s\n' "$out" | grep -E '^not ok|✖' | head -10
fi

# --- 2. la extensión usa las reglas y está instalada ----------------------
if [ -L "$INSTALADA" ]; then
    ok "extensión instalada (symlink)"
else
    fail "tts-summary.ts no está instalado como symlink en ~/.pi/agent/extensions"
fi

grep -q 'from "./lib/tts-cierre.ts"' "$EXT" \
    && ok "usa las reglas puras de lib/tts-cierre.ts" \
    || fail "tts-summary.ts no importa lib/tts-cierre.ts"

grep -q 'esInterrupcion(m.stopReason)' "$EXT" \
    && grep -q 'esInterrupcion((message as { stopReason' "$EXT" \
    && ok "mira la interrupción en message_end y turn_end" \
    || fail "no detecta stopReason de interrupción en los turnos"

grep -q 'if (abortedUntilPrompt) return;' "$EXT" \
    && ok "deliver no habla tras una interrupción" \
    || fail "deliver no respeta el silencio tras interrumpir"

grep -q 'epoch !== abortEpoch' "$EXT" \
    && ok "descarta el cierre asíncrono si el usuario corta" \
    || fail "el resumen en vuelo puede hablar después de una interrupción"

# --- 3. el respaldo de sesión no resucita texto viejo --------------------
grep -q 'esTextoDeLaCorrida(when, runStartedAt)' "$EXT" \
    && ok "el respaldo sólo usa texto de esta corrida" \
    || fail "el respaldo de sesión puede resumir trabajo viejo"

grep -q 'runStartedAt = Date.now()' "$EXT" \
    && ok "marca el arranque de la corrida" \
    || fail "no se registra cuándo arrancó la corrida"

# --- resultado ------------------------------------------------------------
if [ "$fails" -gt 0 ]; then
    echo "$fails falla(s)" >&2
    exit 1
fi
[ "$QUIET" = 1 ] || echo "OK — el cierre hablado se calla si interrumpís"
