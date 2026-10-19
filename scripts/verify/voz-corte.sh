#!/usr/bin/env bash
# verify/voz-corte.sh — cortar la voz (tecla de Windows / `voice stop`) calla
# el TTS en vez de degradarlo a piper/espeak.
#
# Síntoma que protege: si cortabas mientras sonaba Kokoro, `pkill` mataba el
# pw-play y el daemon lo tomaba como "falló el motor" → la MISMA frase seguía
# sonando con piper o espeak (otra voz, peor). Además `pkill -f pw-play` se
# llevaba earcons, chimes y cualquier otro audio del sistema.
#
# Solo lee el repo y corre un arnés en python (sin audio, sin kokoro): no
# necesita estar el servicio levantado ni el micrófono.
#
# Sale 0 si:
#   - un playback cortado no prueba otro motor;
#   - un stop durante la síntesis descarta la frase (no la reproduce después);
#   - un fallo real del motor SÍ sigue cayendo a piper;
#   - `stop` corta sólo el stream "Voice TTS" (no todos los pw-play).
#
# Uso:
#   scripts/verify/voz-corte.sh          # texto
#   scripts/verify/voz-corte.sh --quiet  # solo FALLA
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VOICE="$REPO/linux/voice"
DAEMON="$VOICE/daemon.py"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

[ -f "$DAEMON" ] || { echo "no encuentro $DAEMON" >&2; exit 1; }

# --- 1. reglas de corte: arnés en python, sin audio -----------------------
if out="$(XDG_CACHE_HOME="$(mktemp -d)" VOICE_DIR="$VOICE" python3 - "$DAEMON" <<'PY'
import importlib.util
import os
import sys
import tempfile
import wave

path = sys.argv[1]
sys.path.insert(0, os.path.dirname(path))
spec = importlib.util.spec_from_file_location("voice_daemon", path)
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)

# El harness no toca config ni historial reales.
d.load_config = lambda: {"tts": {"lang": "es"}}
d.tts_command = lambda cfg, lang: {"engine": "kokoro", "voice": "ef_dora"}
d.tts_volume = lambda: 1.0
d.record_history = lambda *a, **k: None
d._duck_enabled = lambda: False


def wav(path, ms=100):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(24000)
        w.writeframes(b"\0\0" * int(24 * ms))


def case_stop_durante_play():
    llamadas = []

    def synth(eng, voice, lang, text, out):
        wav(out)
        llamadas.append(eng)
        return True

    def play(*a, **k):
        d._play_epoch += 1  # `voice stop` mientras suena
        return "cancelled"

    d._synth, d._play = synth, play
    d.synth_and_play({"text": "hola", "record": False})
    assert llamadas == ["kokoro"], f"probó otros motores tras el corte: {llamadas}"


def case_stop_durante_sintesis():
    tocado = []

    def synth(eng, voice, lang, text, out):
        wav(out)
        d._play_epoch += 1  # cortan mientras kokoro sintetiza
        return True

    def play(*a, **k):
        tocado.append(1)
        return "ok"

    d._synth, d._play = synth, play
    d.synth_and_play({"text": "hola", "record": False})
    assert not tocado, "reprodujo una frase que el usuario había cortado"


def case_fallo_real_sigue_cayendo():
    llamadas = []

    def synth(eng, voice, lang, text, out):
        llamadas.append(eng)
        if eng == "kokoro":
            return False  # el motor falló de verdad
        wav(out)
        return True

    def play(*a, **k):
        return "ok"

    d._synth, d._play = synth, play
    asert_ok = d.synth_and_play({"text": "hola", "record": False})
    assert asert_ok, "un fallo real dejó la frase sin voz"
    assert llamadas[:2] == ["kokoro", "piper"], f"cadena inesperada: {llamadas}"


def case_stop_corta_por_pid():
    cortado = []

    class FakeProc:
        def poll(self):
            return None

        def terminate(self):
            cortado.append("term")

        def wait(self, timeout=None):
            return 0

    d._current_play = FakeProc()
    d._queue[:] = [{"text": "pendiente"}]
    antes = d._play_epoch
    d.handle({"cmd": "stop"})
    d._current_play = None
    assert cortado == ["term"], f"stop no cortó el pw-play en curso: {cortado}"
    assert d._play_epoch == antes + 1, "stop no marcó el corte (epoch)"
    assert not d._queue, "stop no vació la cola"


for name, fn in list(globals().items()):
    if name.startswith("case_"):
        fn()
print("casos: corte en play, corte en síntesis, fallback real, corte por pid")
PY
)"; then
    ok "reglas de corte del daemon"
else
    fail "reglas de corte del daemon"
    printf '%s\n' "$out" | tail -5
fi

# --- 2. stop no mata audio ajeno (chequeo de fuente) ----------------------
if grep -v '^[[:space:]]*#' "$DAEMON" | grep -q 'pkill'; then
    fail "el daemon usa pkill (mata audio ajeno)"
else
    ok "stop corta el pw-play en curso por PID (sin pkill)"
fi

if grep -q '"Voice TTS"' "$DAEMON"; then
    ok 'el stream de la voz se identifica como "Voice TTS"'
else
    fail "no reconoce el stream de la voz por nombre"
fi

# --- resultado ------------------------------------------------------------
if [ "$fails" -gt 0 ]; then
    echo "$fails falla(s)" >&2
    exit 1
fi
[ "$QUIET" = 1 ] || echo "OK — cortar la voz la calla, no la degrada"
