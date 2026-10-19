#!/usr/bin/env bash
# verify/cancelar-voz.sh — cancelar la voz es inmediato y calla lo que suena.
#
# Cubre lo que el usuario siente al apretar la tecla de Windows mientras habla
# el TTS:
#   - si Omar está apagado pero hay un aviso sonando, la tecla lo CALLA (antes
#     prendía a Omar y la voz seguía); Escape hace lo mismo;
#   - cerrar Omar corta el audio sin esperar al loop (`voice stop` inmediato) y
#     la señal de cierre va por `listen.pid` + kill(2), sin `systemctl`;
#   - la píldora se consulta por su archivo, no arrancando Quickshell;
#   - la tecla no tiene antirrebote de 800 ms que se coma la segunda pulsación.
#
# Solo lee el repo y corre un arnés en python (sin audio, sin Quickshell, sin
# tocar el Omar vivo). No necesita el servicio levantado.
#
# Uso:
#   scripts/verify/cancelar-voz.sh          # texto
#   scripts/verify/cancelar-voz.sh --quiet  # solo FALLA
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$REPO/linux/bin"
PR="$BIN/present-remote"
KEY="$BIN/voice-key-listener"

fails=0
ok()   { [ "$QUIET" = 1 ] || printf '  ok    %s\n' "$*"; }
fail() { fails=$((fails + 1)); printf '  FALLA %s\n' "$*"; }

[ -f "$PR" ]  || { echo "no encuentro $PR" >&2; exit 1; }
[ -f "$KEY" ] || { echo "no encuentro $KEY" >&2; exit 1; }

# --- 1. reglas de cancelación: arnés en python, sin audio -----------------
if out="$(TMPROOT="$(mktemp -d)" XDG_RUNTIME_DIR="$(mktemp -d)" XDG_CACHE_HOME="$(mktemp -d)" \
          PRESENT_CONFIG=/dev/null python3 - "$PR" <<'PY'
import importlib.machinery
import importlib.util
import json
import os
import signal
import sys
import time

path = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("present_remote", path)
spec = importlib.util.spec_from_loader("present_remote", loader)
pr = importlib.util.module_from_spec(spec)
loader.exec_module(pr)
# Los casos se pisan los stubs entre sí: la señal real se guarda antes.
signal_service_real = pr._signal_service

# El log del script ensucia la salida del verificador.
pr.log = lambda *a, **k: None


def write_speaking(ms_from_now=2000, dur=8000):
    os.makedirs(os.path.dirname(pr.SPEAKING_FILE), exist_ok=True)
    with open(pr.SPEAKING_FILE, "w", encoding="utf-8") as f:
        json.dump({"text": "hola", "startedAt": int(time.time() * 1000),
                   "durationMs": ms_from_now + dur}, f)


def case_tecla_calla_aviso_de_otro():
    """Omar apagado + TTS de otro agente: la tecla lo calla, no lo prende."""
    write_speaking()
    hechos = []
    pr.omar_active = lambda: False
    pr.external_mic_owner = lambda: None
    pr._spawn = lambda *cmd: hechos.append(cmd)
    started = []
    pr.start_voice = lambda: started.append(1)
    pr.toggle_voice()
    assert not started, "prendió Omar encima de la voz que había que callar"
    assert ("voice", "stop") in hechos, f"no cortó el TTS: {hechos}"


def case_tecla_sin_voz_no_corta_nada():
    """Sin TTS sonando, la tecla sigue abriendo Omar."""
    if os.path.exists(pr.SPEAKING_FILE):
        os.remove(pr.SPEAKING_FILE)
    hechos, started = [], []
    pr.omar_active = lambda: False
    pr.external_mic_owner = lambda: None
    pr._spawn = lambda *cmd: hechos.append(cmd)
    pr.start_voice = lambda: started.append(1)
    pr.toggle_voice()
    assert started == [1], "sin nada sonando la tecla tiene que abrir Omar"
    assert ("voice", "stop") not in hechos, "cortó audio que no existía"


def case_escape_calla_aviso():
    """Escape (cancel_key) calla un TTS suelto aunque Omar esté apagado."""
    write_speaking()
    hechos = []
    pr.omar_active = lambda: False
    pr._spawn = lambda *cmd: hechos.append(cmd)
    pr.cut_speaking()
    assert ("voice", "stop") in hechos, "Escape no cortó el TTS suelto"
    os.remove(pr.SPEAKING_FILE)


def case_cerrar_corta_audio_primero():
    """Al cerrar: audio y señal primero, UI después; sin systemctl."""
    orden = []
    pr._signal_service = lambda sig: orden.append(("signal", sig))
    pr._spawn = lambda *cmd: orden.append(cmd)
    pr._ptt_pids = lambda: []
    pr.os.remove = lambda p: None
    pr.cancel_voice()
    assert orden[0] == ("signal", "SIGUSR2"), f"la señal no va primero: {orden}"
    assert ("voice", "stop") in orden[:2], f"el audio no se corta al instante: {orden}"
    assert ("qs", "ipc", "-p", pr.PILL, "call", "omar-pill", "close") in orden, \
        "no cierra la píldora"


def case_senal_por_pid_sin_systemctl():
    """La señal va por listen.pid + kill(2), no levantando systemctl."""
    os.makedirs(os.path.join(pr.RUNTIME, "omar"), exist_ok=True)
    with open(os.path.join(pr.RUNTIME, "omar", "listen.pid"), "w") as f:
        f.write(str(os.getpid()))
    muertes, systemctl = [], []
    real_kill = os.kill
    pr._is_listen_service = lambda pid: True
    pr._systemctl = lambda *a, **k: systemctl.append(a)
    pr.os.kill = lambda pid, sig: muertes.append((pid, sig))
    try:
        signal_service_real("SIGUSR2")
    finally:
        pr.os.kill = real_kill
    assert muertes == [(os.getpid(), signal.SIGUSR2)], f"no usó kill(2): {muertes}"
    assert not systemctl, f"levantó systemctl en el camino rápido: {systemctl}"


def case_pildora_por_archivo():
    """pill_is_open lee el archivo; no arranca Quickshell."""
    os.makedirs(os.path.join(pr.RUNTIME, "omar"), exist_ok=True)
    with open(pr.PILL_OPEN, "w") as f:
        f.write("1")
    real = pr.subprocess.check_output

    def boom(*a, **k):
        raise AssertionError("arrancó Quickshell para leer la píldora")

    pr.subprocess.check_output = boom
    try:
        assert pr.pill_is_open() is True, "no leyó pill-open"
    finally:
        pr.subprocess.check_output = real
    with open(pr.PILL_OPEN, "w") as f:
        f.write("0")
    assert pr.pill_is_open() is False, "no respeta pill-open = 0"


for name, fn in list(globals().items()):
    if name.startswith("case_"):
        fn()
print("casos: tecla calla aviso, tecla sin voz, escape, orden de cierre, "
      "señal por pid, píldora por archivo")
PY
)"; then
    ok "reglas de cancelación (present-remote)"
else
    fail "reglas de cancelación (present-remote)"
    printf '%s\n' "$out" | tail -6
fi

# --- 2. la tecla no tiene antirrebote por tiempo --------------------------
if grep -q 'now - last > 800' "$KEY"; then
    fail "voice-key-listener se come la segunda pulsación rápida (800 ms)"
else
    ok "la tecla responde en cada pulsación (sin antirrebote de 800 ms)"
fi

if grep -q '"${TOGGLE_CMD\[@\]}"' "$KEY"; then
    ok "la tecla ejecuta la acción configurada"
else
    fail "no ejecuta la acción configurada"
fi

# --- resultado ------------------------------------------------------------
if [ "$fails" -gt 0 ]; then
    echo "$fails falla(s)" >&2
    exit 1
fi
[ "$QUIET" = 1 ] || echo "OK — cancelar calla la voz al instante"
