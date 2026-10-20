#!/usr/bin/env bash
# verify/voz-dictado.sh — la voz nunca habla encima de un dictado.
#
# Síntoma que protege: estabas dictando y un aviso hablado (el cierre de un
# agente, una notificación) se puso a hablar. El TTS sonaba en el micrófono y
# tus palabras salían mezcladas con las del mensaje. Ahora la regla es una sola:
# si hay dictado, la voz espera; si el dictado empieza con la voz sonando, se
# corta y la frase vuelve a la cola.
#
# Solo lee el repo y corre un arnés en python (sin audio, sin kokoro): no
# necesita el servicio levantado ni el micrófono.
#
# Sale 0 si:
#   - micguard distingue dictado vivo de anotación muerta, vieja o reusada;
#   - el daemon no sintetiza mientras hay dictado y retoma la cola al liberarse;
#   - un dictado que empieza con la voz sonando corta la reproducción y la frase
#     queda en la cola;
#   - los caminos directos del CLI (sin daemon, repeat, inbox, play) esperan.
#
# Uso:
#   scripts/verify/voz-dictado.sh          # texto
#   scripts/verify/voz-dictado.sh --quiet  # solo FALLA
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VOICE="$REPO/linux/voice"
DAEMON="$VOICE/daemon.py"
GUARD="$VOICE/micguard.py"
CLI="$REPO/linux/bin/voice"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

[ -f "$DAEMON" ] || { echo "no encuentro $DAEMON" >&2; exit 1; }
[ -f "$GUARD" ]  || { echo "no encuentro $GUARD" >&2; exit 1; }
[ -f "$CLI" ]    || { echo "no encuentro $CLI" >&2; exit 1; }

# --- 1. arnés: micguard + daemon, sin audio -------------------------------
if out="$(VOICE_DIR="$VOICE" python3 - "$DAEMON" "$GUARD" <<'PY'
import importlib.util
import os
import sys
import tempfile
import threading
import time

daemon_path, guard_path = sys.argv[1], sys.argv[2]

# Un dictado falso: un proceso cuyo cmdline contiene "dictate" (así lo reconoce
# micguard) y que vive mientras dura el arnés.
folder = tempfile.mkdtemp()
omar = os.path.join(folder, "omar")
os.makedirs(omar, exist_ok=True)
falso = os.path.join(folder, "omar-dictate")
with open(falso, "w") as fh:
    fh.write("#!/bin/sh\nsleep 120\n")
os.chmod(falso, 0o755)
import subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(daemon_path)))
dictado = subprocess.Popen([falso], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
os.environ["XDG_RUNTIME_DIR"] = folder
time.sleep(0.1)


def importar(nombre, path):
    spec = importlib.util.spec_from_file_location(nombre, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


g = importar("micguard", guard_path)
d = importar("voice_daemon", daemon_path)
d.micguard = g

fallos = []


def check(nombre, cond):
    if not cond:
        fallos.append(nombre)


# micguard: libre sin anotaciones
check("micguard libre", g.busy() is False)

bandera = os.path.join(omar, "mic-busy")
turno = os.path.join(omar, "dictate.pid")

# viva
with open(bandera, "w") as fh:
    fh.write(str(dictado.pid))
check("mic-busy vivo = dictando", g.busy() is True)
os.remove(bandera)

# muerta
muerto = subprocess.Popen([falso], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
pid_muerto = muerto.pid
muerto.kill()
muerto.wait()
with open(bandera, "w") as fh:
    fh.write(str(pid_muerto))
check("bandera de proceso muerto", g.busy() is False)
os.remove(bandera)

# vieja
with open(turno, "w") as fh:
    fh.write(str(dictado.pid))
viejo = time.time() - 10 * 60
os.utime(turno, (viejo, viejo))
check("turno caducado", g.busy() is False)
os.remove(turno)

# pid reusado (vivo pero no es un dictado)
with open(bandera, "w") as fh:
    fh.write(str(os.getpid()))
check("pid reusado no cuenta", g.busy() is False)
os.remove(bandera)

# el turno del gesto también cuenta
with open(turno, "w") as fh:
    fh.write(str(dictado.pid))
check("dictate.pid vivo = dictando", g.busy() is True)

# ── daemon: no sintetiza mientras hay dictado ──────────────────────────
d.load_config = lambda: {"tts": {"lang": "es"}}
d.tts_command = lambda cfg, lang: {"engine": "kokoro", "voice": "ef_dora"}
d.tts_volume = lambda: 1.0
d.record_history = lambda *a, **k: None
d._duck_enabled = lambda: False
d._publish_speaking = lambda *a, **k: None
anotado = []
d._annotate_spoken = lambda t: anotado.append(t)

sintetizadas = []
d._synth = lambda *a, **k: (sintetizadas.append(a), True)[1]

# worker: con dictado activo no arranca (la frase espera en la cola)
pedidos = []
synth_real = d.synth_and_play
d.synth_and_play = lambda req: pedidos.append(req)
d._queue.append({"text": "aviso de prueba"})
hilo = threading.Thread(target=d.worker, daemon=True)
hilo.start()
time.sleep(0.9)
check("con dictado no arranca", pedidos == [])
check("la frase no se pierde", len(d._queue) == 1)
d._stop = True
hilo.join(timeout=2)

# worker: al liberarse el micrófono, sigue con la cola
os.remove(turno)
d._stop = False
hilo = threading.Thread(target=d.worker, daemon=True)
hilo.start()
time.sleep(0.9)
check("al liberarse arranca", [p.get("text") for p in pedidos] == ["aviso de prueba"])
d._stop = True
hilo.join(timeout=2)

# ── daemon: dictado a mitad del playback ───────────────────────────────
# _play() tiene que cortar y devolver "dictated" (la frase se reencola).
class FalsoProceso:
    def __init__(self):
        self.terminado = False
        self.esperas = 0

    def wait(self, timeout=None):
        self.esperas += 1
        if self.terminado:
            return 0
        if self.esperas > 4:  # el audio "termina" solo
            self.terminado = True
            return 0
        time.sleep(0.05)
        raise subprocess.TimeoutExpired("pw-play", timeout)

    def poll(self):
        return None if not self.terminado else 0

    def terminate(self):
        self.terminado = True

    def kill(self):
        self.terminado = True


falso_proc = FalsoProceso()
d.subprocess.Popen = lambda *a, **k: falso_proc
wav = os.path.join(folder, "voz.wav")
open(wav, "wb").close()

d.micguard = g
with open(turno, "w") as fh:
    fh.write(str(dictado.pid))
corto = []
d._stop_playback = lambda: (corto.append(True), falso_proc.terminate())
r = d._play(wav, text="hola", source="prueba")
check("dictado a mitad de frase corta la voz", r == "dictated")
check("y se anota la hora real del audio", bool(anotado))

# sin dictado, reproduce normal
os.remove(turno)
d._stop_playback = lambda: None
falso_proc.terminado = False
falso_proc.esperas = 0
r = d._play(wav, text="hola", source="prueba")
check("sin dictado reproduce", r == "ok")

# synth_and_play reencola lo cortado por dictado
d.micguard = g
with open(turno, "w") as fh:
    fh.write(str(dictado.pid))
d._queue.clear()
original = d._play
d._play = lambda *a, **k: "dictated"
synth_real({"text": "frase cortada"})
d._play = original
check("lo cortado por dictado vuelve a la cola",
      [q.get("text") for q in d._queue] == ["frase cortada"])

dictado.kill()
if fallos:
    for f in fallos:
        print("FALLA-CASO " + f)
    sys.exit(1)
print("casos ok")
PY
)"; then
  ok "arnés: ${out:-casos ok}"
else
  fail "arnés de dictado/voz"
  printf '%s\n' "$out" | grep 'FALLA-CASO' | sed 's/FALLA-CASO /        /'
fi

# --- 2. los caminos directos del CLI también esperan ---------------------
for fn in "__speak_direct" "repeat()" "play_inbox()"; do
  if awk "/^${fn%.*}\\(\\)/{en=1} en&&/wait_mic_free/{found=1} en&&/^}/{if(found)exit 0; en=0} END{exit !found}" "$CLI"; then
    ok "CLI ${fn%.*} espera al dictado"
  else
    fail "CLI ${fn%.*} no espera al dictado"
  fi
done
if grep -q 'mic_busy() { "$PY" "$VOICE_DIR/micguard.py" --busy' "$CLI"; then
  ok "CLI pregunta con la misma regla (micguard)"
else
  fail "CLI no usa micguard"
fi

# --- 3. el daemon usa el guard antes y durante ---------------------------
if grep -q 'if _dictation_active():' "$DAEMON" && \
   grep -q 'return "dictated"' "$DAEMON"; then
  ok "daemon: espera y corta por dictado"
else
  fail "daemon sin guard de dictado"
fi
if grep -q 'import micguard' "$DAEMON"; then
  ok "daemon: una sola regla (micguard)"
else
  fail "daemon no importa micguard"
fi

if [ "$fails" -eq 0 ]; then
  [ "$QUIET" = 1 ] || printf '\nvoz-dictado: todo ok\n'
  exit 0
fi
printf '\nvoz-dictado: %d falla(s)\n' "$fails" >&2
exit 1
