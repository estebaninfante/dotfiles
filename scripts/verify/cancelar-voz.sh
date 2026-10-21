#!/usr/bin/env bash
# verify/cancelar-voz.sh — cancelar la voz es inmediato y calla TODO.
#
# Cubre lo que el usuario siente al apretar la tecla de Windows mientras habla
# el TTS: la tecla no es "cerrá la píldora", es "apagá lo que esté pasando".
#   - si hay un aviso sonando, la tecla lo CALLA, saca los subtítulos (glow) y
#     el cartel de escritorio de ese aviso (antes sólo cortaba el audio y el
#     mensaje quedaba en pantalla);
#   - si está dictando, cancela el dictado con SIGINT (= descartar), para que no
#     siga grabando ni escriba el texto después de la tecla;
#   - cerrar corta el audio sin esperar al loop (`voice stop` inmediato), cierra
#     píldora y glow, y la señal va por `listen.pid` + kill(2), sin `systemctl`;
#   - la píldora se consulta por su archivo, no arrancando Quickshell;
#   - la tecla no tiene antirrebote de 800 ms que se coma la segunda pulsación;
#   - Escape cancela lo mismo, pero sólo si hay algo en curso.
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
import shutil
import signal
import subprocess
import sys
import time

path = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("present_remote", path)
spec = importlib.util.spec_from_loader("present_remote", loader)
pr = importlib.util.module_from_spec(spec)
loader.exec_module(pr)
# Los casos se pisan los stubs entre sí: la señal real se guarda antes.
signal_service_real = pr._signal_service
omar_active_real = pr.omar_active
pill_is_open_real = pr.pill_is_open
# El log del script ensucia la salida del verificador.
pr.log = lambda *a, **k: None


def write_speaking(source="jaguar", dur=8000):
    os.makedirs(os.path.dirname(pr.SPEAKING_FILE), exist_ok=True)
    with open(pr.SPEAKING_FILE, "w", encoding="utf-8") as f:
        json.dump({"text": "hola", "source": source, "color": "#89b4fa",
                   "startedAt": int(time.time() * 1000),
                   "durationMs": dur}, f)


def clear_speaking():
    try:
        os.remove(pr.SPEAKING_FILE)
    except FileNotFoundError:
        pass


def fake_dictation():
    """Un proceso vivo cuya línea de comandos dice 'dictate', como el de Omar.

    Se copia `sleep` con un nombre que contiene 'dictate': así el chequeo de
    pid reusado de `dictate_pid()` lo reconoce sin arrancar Omar de verdad.
    """
    exe = os.path.join(os.path.dirname(pr.DICTATE_PID), "dictate-test")
    os.makedirs(os.path.dirname(pr.DICTATE_PID), exist_ok=True)
    shutil.copy("/bin/sleep", exe)
    proc = subprocess.Popen([exe, "30"])
    with open(pr.DICTATE_PID, "w", encoding="utf-8") as f:
        f.write(str(proc.pid))
    return proc


def case_tecla_calla_aviso_de_otro():
    """TTS de otro agente + Omar apagado: la tecla calla y NO prende nada."""
    write_speaking("jaguar")
    hechos, started = [], []
    pr.omar_active = lambda: False
    pr.external_mic_owner = lambda: None
    pr._spawn = lambda *cmd: hechos.append(cmd)
    pr.start_voice = lambda: started.append(1)
    try:
        pr.toggle_voice()
    finally:
        clear_speaking()
    assert not started, "prendió Omar encima de la voz que había que callar"
    assert ("voice", "stop") in hechos, f"no cortó el TTS: {hechos}"
    assert ("qs", "ipc", "-p", pr.GLOW, "call", "omar-glow", "hide") in hechos, \
        f"dejó los subtítulos en pantalla: {hechos}"
    assert ("qs", "-p", pr.OMARCHY_SHELL, "ipc", "call", "notifications",
            "dismiss", "jaguar") in hechos, f"dejó el cartel del aviso: {hechos}"


def case_tecla_sin_nada_no_corta_nada():
    """Sin TTS ni Omar, la tecla sigue abriendo Omar."""
    clear_speaking()
    hechos, started = [], []
    pr.omar_active = lambda: False
    pr.external_mic_owner = lambda: None
    pr._spawn = lambda *cmd: hechos.append(cmd)
    pr.start_voice = lambda: started.append(1)
    pr.toggle_voice()
    assert started == [1], "sin nada sonando la tecla tiene que abrir Omar"
    assert ("voice", "stop") not in hechos, "cortó audio que no existía"


def case_tecla_con_dictado_cancela():
    """Dictando: la tecla descarta el dictado y no abre Omar encima."""
    clear_speaking()
    dictado = fake_dictation()
    hechos, started = [], []
    pr.pill_is_open = lambda: False
    pr.service_awake = lambda: False
    pr.ptt_active = lambda: False
    pr.omar_active = omar_active_real   # así se ejercita dictate_active() de verdad
    pr._ptt_pids = lambda: []
    pr.external_mic_owner = lambda: None
    pr._signal_service = lambda sig: None
    pr._spawn = lambda *cmd: hechos.append(cmd)
    pr.start_voice = lambda: started.append(1)
    try:
        pr.toggle_voice()
        vivo = dictado.poll() is None
    finally:
        if dictado.poll() is None:
            dictado.kill()
            dictado.wait()
        try:
            os.remove(pr.DICTATE_PID)
        except FileNotFoundError:
            pass
    assert not started, "abrió Omar mientras había un dictado en curso"
    assert not vivo, "dejó el dictado grabando (el texto se habría escrito igual)"
    assert ("voice", "stop") in hechos, f"no calló el audio: {hechos}"
    assert ("qs", "ipc", "-p", pr.PILL, "call", "omar-pill", "close") in hechos, \
        "no cerró la píldora"


def case_cerrar_corta_audio_primero():
    """Al cancelar: señal y audio primero, UI en el mismo instante, sin systemctl."""
    write_speaking("jaguar")
    orden = []
    pr._signal_service = lambda sig: orden.append(("signal", sig))
    pr._spawn = lambda *cmd: orden.append(cmd)
    pr._ptt_pids = lambda: []
    pr.cancel_dictation = lambda: orden.append(("dictation",))
    try:
        pr.cancel_voice()
    finally:
        clear_speaking()
    assert orden[0] == ("signal", "SIGUSR2"), f"la señal no va primero: {orden}"
    assert ("voice", "stop") in orden[:2], f"el audio no se corta al instante: {orden}"
    assert ("qs", "ipc", "-p", pr.PILL, "call", "omar-pill", "close") in orden, \
        "no cierra la píldora"
    assert ("qs", "ipc", "-p", pr.GLOW, "call", "omar-glow", "hide") in orden, \
        "no apaga el glow"
    assert ("qs", "-p", pr.OMARCHY_SHELL, "ipc", "call", "notifications",
            "dismiss", "jaguar") in orden, "no saca el cartel del aviso"
    assert ("dictation",) in orden, "no cancela el dictado"
    assert orden.index(("dictation",)) > orden.index(("voice", "stop")), \
        f"la UI espera al dictado: {orden}"


def case_escape_cancela_solo_si_hay_algo():
    """Escape hace lo mismo que la tecla, pero no toca nada si está todo quieto."""
    class Stream:
        def __init__(self, line):
            self.line = line

        def readline(self):
            return self.line

    hechos = []
    pr.cancel_voice = lambda: hechos.append("cancel")
    linea = "kbd\t1\tesc down\n"
    pr.handle_event(Stream(linea), {}, {"cancel_key": "esc"}, {})
    assert hechos == [], f"Escape canceló con todo quieto: {hechos}"
    pr.omar_active = lambda: True
    pr.handle_event(Stream(linea), {}, {"cancel_key": "esc"}, {})
    assert hechos == ["cancel"], f"Escape no canceló: {hechos}"


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
    pr.pill_is_open = pill_is_open_real   # otro caso lo stubeó
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
print("casos: tecla calla aviso, tecla sin nada, dictado, orden de cierre, "
      "escape, señal por pid, píldora por archivo")
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
[ "$QUIET" = 1 ] || echo "OK — cancelar calla la voz al instante y saca la UI"
