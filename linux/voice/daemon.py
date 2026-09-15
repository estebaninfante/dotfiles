#!/usr/bin/env python3
# daemon.py — voice-daemon: cola de TTS + reproduccion para el sistema de voz.
#
# Capa daemon (systemd user service). NO sabe nada de OpenCode ni STT:
# solo sintetiza y reproduce texto. La integracion de eventos opencode
# (plugin voice) escriben por el FIFO; el CLI `voice speak` tambien.
#
# Protocolo FIFO (~/.cache/voice/tts.fifo), JSON por linea:
#   {"text": "...", "voice": "es_MX-claude-high", "lang": "es",
#    "engine": "piper", "priority": 1, "key": "idle-abc"}
#   {"cmd": "stop"}        # vacía la cola y corta la reproducción actual
#   {"cmd": "flush"}       # vacía la cola sin cortar lo que suena
#   {"cmd": "reload"}      # recarga config/estado
#   {"cmd": "status"}      # responde por el FIFO de respuesta si existe
#
# Dedup: si llega una petición con la misma `key` dentro del TTL se ignora
# (varios procesos/instancias de opencode pueden emitir el mismo evento).
#
# Motor TTS conmuta por config/estado (engine = chatterbox|piper|kokoro|espeak),
# resuelto durante el arranque. Chatterbox usa GPU (CUDA), demas en CPU.

import json
import os
import select
import signal
import subprocess
import sys
import tempfile
import time

from engine import (
    CACHE_DIR,
    find_piper_model,
    load_config,
    save_state,
    tts_command,
)

FIFO = os.environ.get("VOICE_TTS_FIFO", os.path.join(CACHE_DIR, "tts.fifo"))
PID_FILE = os.path.join(CACHE_DIR, "daemon.pid")
LOG_FILE = os.environ.get("VOICE_LOG", os.path.join(CACHE_DIR, "daemon.log"))
DEDUP_TTL = float(os.environ.get("VOICE_DEDUP_TTL", "20"))

_last_key: dict[str, float] = {}
_queue: list[dict] = []
_stop = False
_chatterbox_proc: subprocess.Popen | None = None


def log(msg: str) -> None:
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as fh:
            fh.write(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")
    except OSError:
        pass


# ── Chatterbox server lifecycle ──────────────────────────────────────────
def _ensure_chatterbox_server() -> subprocess.Popen | None:
    """Start or restart the persistent chatterbox server. Returns the Popen."""
    global _chatterbox_proc

    # Check if existing server is alive
    if _chatterbox_proc is not None:
        rc = _chatterbox_proc.poll()
        if rc is None:
            return _chatterbox_proc  # still running
        log(f"chatterbox server died (rc={rc}), restarting")
        _chatterbox_proc = None

    venv_python = os.path.expanduser("~/.local/share/tts/venv/bin/python3")
    if not os.path.exists(venv_python):
        log("chatterbox: venv python no encontrado")
        return None

    script = os.path.join(os.path.dirname(__file__), "chatterbox_server.py")
    if not os.path.exists(script):
        log(f"chatterbox: server script no encontrado: {script}")
        return None

    log("chatterbox server starting...")
    try:
        proc = subprocess.Popen(
            [venv_python, script],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,  # line-buffered
        )
        _chatterbox_proc = proc

        # Wait for "Ready" on stderr (model loaded)
        import threading
        def _read_stderr():
            for line in proc.stderr:
                line = line.rstrip()
                if line:
                    log(f"chatterbox: {line}")
        threading.Thread(target=_read_stderr, daemon=True).start()

        # Ping to confirm readiness (wait up to 30s for model load)
        time.sleep(2)
        resp = _server_request({"ping": True}, timeout=30)
        if resp and resp.get("pong"):
            log("chatterbox server ready")
            return proc
        else:
            log("chatterbox server failed to respond to ping")
            proc.terminate()
            _chatterbox_proc = None
            return None
    except Exception as e:
        log(f"chatterbox server start failed: {e}")
        _chatterbox_proc = None
        return None


def _server_request(req: dict, timeout: float = 120) -> dict | None:
    """Send JSON request to chatterbox server, return response dict."""
    global _chatterbox_proc
    proc = _chatterbox_proc
    if proc is None or proc.poll() is not None:
        return None
    try:
        proc.stdin.write(json.dumps(req) + "\n")
        proc.stdin.flush()
        ready, _, _ = select.select([proc.stdout], [], [], timeout)
        if not ready:
            log("chatterbox server timeout")
            return None
        line = proc.stdout.readline()
        if not line:
            log("chatterbox server EOF")
            return None
        return json.loads(line)
    except Exception as e:
        log(f"chatterbox server communicate error: {e}")
        return None


def _shutdown_chatterbox_server():
    """Gracefully shut down the chatterbox server."""
    global _chatterbox_proc
    if _chatterbox_proc is None:
        return
    try:
        _chatterbox_proc.stdin.write(json.dumps({"shutdown": True}) + "\n")
        _chatterbox_proc.stdin.flush()
        _chatterbox_proc.wait(timeout=5)
    except Exception:
        try:
            _chatterbox_proc.terminate()
        except Exception:
            pass
    _chatterbox_proc = None


# ── Sintesis + reproduccion ─────────────────────────────────────────────
def synth_and_play(req: dict) -> bool:
    """Sintetiza `req['text']` y reproduce. Router TTS por-idioma con
    cadena de fallback: motor principal → piper → espeak.
    """
    cfg = load_config()
    lang = req.get("lang") or cfg["tts"]["lang"]
    tcfg = tts_command(cfg, lang)
    engine = req.get("engine") or tcfg["engine"]
    voice = req.get("voice") or tcfg["voice"]
    text = req.get("text", "").strip()
    if not text:
        return False

    wav = os.path.join(tempfile.gettempdir(),
                       f"voice-{os.getpid()}-{int(time.time()*1000)}.wav")

    # Cadena de motores a probar en orden. engine puede estar explícito en req.
    chain = [engine] + [s for s in ("piper", "espeak") if s != engine]
    ok = False
    for eng in chain:
        ok = _synth(eng, voice, lang, text, wav) and _play(wav)
        if ok:
            break
        log(f"fallback: {eng} -> siguiente motor de la cadena")
        if os.path.exists(wav):
            try:
                os.remove(wav)
            except OSError:
                pass

    try:
        if os.path.exists(wav):
            os.remove(wav)
    except OSError:
        pass
    return ok


def _synth(engine: str, voice: str, lang: str, text: str, wav: str) -> bool:
    """Sintetiza `text` a `wav` con el motor dado. Devuelve OK (wav creado)."""
    if engine == "chatterbox":
        proc = _ensure_chatterbox_server()
        if proc is None:
            return False
        ref_dir = os.path.join(os.path.expanduser("~"), ".local", "share", "tts", "chatterbox", "refs")
        ref_file = os.path.join(ref_dir, f"ref_{lang}.wav")
        req = {"text": text, "output": wav, "lang": lang}
        if os.path.isfile(ref_file):
            req["ref"] = ref_file
        resp = _server_request(req, timeout=120)
        if resp and resp.get("ok"):
            stats = resp.get("stats", {})
            log(f"chatterbox: {stats.get('synth_time', '?')}s synth, "
                f"{stats.get('duration', '?')}s audio, RTF={stats.get('rtf', '?')}")
            return True
        else:
            err = resp.get("error", "unknown") if resp else "no response"
            log(f"chatterbox synth fail: {err}")
            return False
    if engine == "piper":
        model = find_piper_model(voice)
        if not model:
            log(f"piper: voz '{voice}' no instalada")
            return False
        rate = _piper_sample_rate(model + ".json")
        return _run(["piper", "--model", model, "--output_file", wav], text)
    if engine == "kokoro":
        kokoro = "/run/current-system/sw/bin/voice-kokoro"
        if not os.path.exists(kokoro):
            log("kokoro: wrapper voice-kokoro no disponible")
            return False
        langc = "en" if lang == "en" else "es"
        return _run([kokoro, "-o", wav, "-l", langc, "-t", text, "-v", voice], None)
    # espeak (final)
    return _run(["espeak-ng", "-v", lang, "-s", "160", "-p", "50", "-w", wav, text], None)


def _piper_sample_rate(json_path: str) -> int | None:
    try:
        import json as _j
        with open(json_path, "r", encoding="utf-8") as fh:
            data = _j.load(fh)
        return int(data.get("audio", {}).get("sample_rate", 22050))
    except Exception:
        return 22050


def _run(argv: list[str], text: str | None) -> bool:
    """Ejecuta el comando de sintesis. `text` via stdin (null = argumento)."""
    try:
        if text is None:
            r = subprocess.run(argv, capture_output=True, timeout=300)
        else:
            r = subprocess.run(argv, input=text, capture_output=True, text=True, timeout=300)
        if r.returncode != 0:
            log(f"synth fail: {' '.join(argv[:3])} rc={r.returncode}: {r.stderr[-300:]}")
            return False
        return True
    except Exception as e:
        log(f"synth error: {e}")
        return False


def _play(wav: str) -> bool:
    if not os.path.isfile(wav):
        return False
    argv = ["pw-play", wav]
    try:
        r = subprocess.run(argv, capture_output=True, timeout=900)
        if r.returncode != 0:
            return False
        return True
    except Exception as e:
        log(f"play error: {e}")
        return False


# ── Cola ────────────────────────────────────────────────────────────────
def enqueue(req: dict) -> None:
    key = req.get("key")
    now = time.time()
    if key:
        prev = _last_key.get(key, 0)
        if now - prev < DEDUP_TTL:
            log(f"dedup (skip): {key}")
            return
        _last_key[key] = now
        # poda de claves viejas (evita crecimiento)
        for k in [k for k, t in _last_key.items() if now - t > 3600]:
            _last_key.pop(k, None)
    if req.get("priority", 1) >= 2:
        _queue.insert(0, req)
    else:
        _queue.append(req)
    log(f"enqueue: {' '.join(str(req.get('text', ''))[:60].split()) or '(cmd)'}")


def worker() -> None:
    global _stop
    while True:
        if _stop:
            return
        if not _queue:
            time.sleep(0.2)
            continue
        req = _queue.pop(0)
        synth_and_play(req)


# ── FIFO IO ─────────────────────────────────────────────────────────────
def ensure_fifo() -> None:
    os.makedirs(os.path.dirname(FIFO), exist_ok=True)
    if os.path.exists(FIFO) and not os.path.isfile(FIFO):
        os.remove(FIFO)
    if not os.path.exists(FIFO):
        import stat
        os.mkfifo(FIFO, 0o600)


def handle(req: dict) -> None:
    cmd = req.get("cmd")
    if cmd == "stop":
        _queue.clear()
        subprocess.run(["pkill", "-f", "pw-play"], capture_output=True)
        log("cmd=stop (cola vaciada + playback detenido)")
    elif cmd == "flush":
        _queue.clear()
        log("cmd=flush")
    elif cmd == "reload":
        log("cmd=reload")
    elif cmd:
        log(f"cmd desconocido: {cmd}")
    else:
        enqueue(req)


def main() -> None:
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(PID_FILE, "w") as fh:
        fh.write(str(os.getpid()))

    def _term(_s, _f):
        log("SIGTERM — saliendo")
        _shutdown_chatterbox_server()
        sys.exit(0)

    def _hup(_s, _f):
        log("SIGHUP — recargando config")
        load_config()

    signal.signal(signal.SIGTERM, _term)
    signal.signal(signal.SIGHUP, _hup)

    log("voice-daemon arrancado")
    ensure_fifo()

    import threading
    threading.Thread(target=worker, daemon=True).start()

    # read loop bloqueante
    while True:
        try:
            with open(FIFO, "r", encoding="utf-8") as fh:
                for line in fh:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        req = json.loads(line)
                    except json.JSONDecodeError:
                        log(f"linea invalida: {line[:120]}")
                        continue
                    handle(req)
        except OSError as e:
            log(f"fifo error: {e} — reintento en 2s")
            time.sleep(2)
            ensure_fifo()


if __name__ == "__main__":
    main()