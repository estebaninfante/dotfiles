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
import re
import select
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time

from engine import (
    CACHE_DIR,
    find_piper_model,
    load_config,
    record_history,
    save_state,
    tts_command,
    tts_volume,
)

FIFO = os.environ.get("VOICE_TTS_FIFO", os.path.join(CACHE_DIR, "tts.fifo"))
PID_FILE = os.path.join(CACHE_DIR, "daemon.pid")
LOG_FILE = os.environ.get("VOICE_LOG", os.path.join(CACHE_DIR, "daemon.log"))
SYNTH_SOCK = os.environ.get("VOICE_SYNTH_SOCK", os.path.join(CACHE_DIR, "synth.sock"))
# Estado de lo que se está hablando AHORA (para subtítulos karaoke en el glow).
SPEAKING_FILE = os.environ.get("VOICE_SPEAKING_FILE", os.path.join(CACHE_DIR, "speaking.json"))
DEDUP_TTL = float(os.environ.get("VOICE_DEDUP_TTL", "20"))

_last_key: dict[str, float] = {}
_queue: list[dict] = []
_stop = False
_chatterbox_proc: subprocess.Popen | None = None
_chatterbox_lock = threading.Lock()
_kokoro_proc: subprocess.Popen | None = None
_kokoro_lock = threading.Lock()


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


def _ensure_kokoro_server() -> subprocess.Popen | None:
    """Start or restart the persistent kokoro server. Returns the Popen."""
    global _kokoro_proc

    if _kokoro_proc is not None:
        rc = _kokoro_proc.poll()
        if rc is None:
            return _kokoro_proc
        log(f"kokoro server died (rc={rc}), restarting")
        _kokoro_proc = None

    venv_python = os.path.expanduser("~/.local/share/tts/venv-kokoro/bin/python")
    if not os.path.exists(venv_python):
        log("kokoro: venv python no encontrado")
        return None

    script = os.path.join(os.path.dirname(__file__), "kokoro_server.py")
    if not os.path.exists(script):
        log(f"kokoro: server script no encontrado: {script}")
        return None

    log("kokoro server starting...")
    try:
        proc = subprocess.Popen(
            [venv_python, script],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        _kokoro_proc = proc

        def _read_stderr():
            for line in proc.stderr:
                line = line.rstrip()
                if line:
                    log(f"kokoro: {line}")
        threading.Thread(target=_read_stderr, daemon=True).start()

        time.sleep(2)
        resp = _server_request({"ping": True}, timeout=90, proc=proc)
        if resp and resp.get("pong"):
            log("kokoro server ready")
            return proc
        log("kokoro server failed to respond to ping")
        proc.terminate()
        _kokoro_proc = None
        return None
    except Exception as e:
        log(f"kokoro server start failed: {e}")
        _kokoro_proc = None
        return None


def _server_request(req: dict, timeout: float = 120,
                    proc: subprocess.Popen | None = None) -> dict | None:
    """Send JSON request to a persistent TTS server, return response dict."""
    proc = proc if proc is not None else _chatterbox_proc
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


def _shutdown_kokoro_server():
    """Gracefully shut down the kokoro server."""
    global _kokoro_proc
    if _kokoro_proc is None:
        return
    try:
        _kokoro_proc.stdin.write(json.dumps({"shutdown": True}) + "\n")
        _kokoro_proc.stdin.flush()
        _kokoro_proc.wait(timeout=5)
    except Exception:
        try:
            _kokoro_proc.terminate()
        except Exception:
            pass
    _kokoro_proc = None


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
    pitch = _as_float(req.get("pitch"), 0.0)
    speed = _as_float(req.get("speed"), 1.0)
    ok = False
    played_engine = ""
    for eng in chain:
        if not _synth(eng, voice, lang, text, wav):
            log(f"fallback: {eng} -> siguiente motor de la cadena")
            if os.path.exists(wav):
                try:
                    os.remove(wav)
                except OSError:
                    pass
            continue
        # Tono/velocidad del perfil ("personalidad"): mismo motor, otra voz.
        _apply_effects(wav, pitch, speed)
        if _play(wav, text=text, source=req.get("source") or "voice", engine=eng, voice=voice):
            ok = True
            played_engine = eng
            break
        log(f"fallback: {eng} -> siguiente motor de la cadena")
        if os.path.exists(wav):
            try:
                os.remove(wav)
            except OSError:
                pass

    if ok and req.get("record", True):
        # El WAV pasa al historial (se mueve): queda disponible para repasarlo
        # desde el widget de la barra. No se borra si falla la anotacion.
        record_history(wav, text, played_engine, voice, lang,
                       req.get("source") or "voice")
    # Si record_history lo movio, esto ya no encuentra nada; si fallo la
    # sintesis, limpia el temporal.
    try:
        if os.path.exists(wav):
            os.remove(wav)
    except OSError:
        pass
    return ok


def _as_float(value, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _apply_effects(wav: str, pitch: float, speed: float) -> None:
    """Aplica tono (semitonos) y tempo (factor) con sox, in place.

    Multiplica las "personalidades" posibles: la misma voz base con distinto
    tono suena a alguien distinto. Si sox falta o falla, deja el WAV intacto.
    """
    if abs(pitch) < 1e-3 and abs(speed - 1.0) < 1e-3:
        return
    if not os.path.isfile(wav) or not shutil.which("sox"):
        return
    out = wav + ".fx.wav"
    argv = ["sox", wav, out]
    if abs(pitch) >= 1e-3:
        argv += ["pitch", str(int(round(pitch * 100)))]
    if abs(speed - 1.0) >= 1e-3:
        argv += ["tempo", f"{speed:.3f}"]
    try:
        r = subprocess.run(argv, capture_output=True, timeout=180)
    except Exception as e:
        log(f"sox effects error: {e}")
        return
    if r.returncode == 0 and os.path.isfile(out):
        os.replace(out, wav)
    else:
        log(f"sox effects fallo rc={r.returncode}: {r.stderr[-200:]}")
        try:
            if os.path.exists(out):
                os.remove(out)
        except OSError:
            pass


def _synth(engine: str, voice: str, lang: str, text: str, wav: str) -> bool:
    """Sintetiza `text` a `wav` con el motor dado. Devuelve OK (wav creado)."""
    if engine == "chatterbox":
        ref_dir = os.path.join(os.path.expanduser("~"), ".local", "share", "tts", "chatterbox", "refs")
        ref_file = os.path.join(ref_dir, f"ref_{lang}.wav")
        req = {"text": text, "output": wav, "lang": lang}
        if os.path.isfile(ref_file):
            req["ref"] = ref_file
        # El server chatterbox es single-threaded (stdin/stdout); serializar.
        with _chatterbox_lock:
            proc = _ensure_chatterbox_server()
            if proc is None:
                return False
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
        with _kokoro_lock:
            proc = _ensure_kokoro_server()
            if proc is not None:
                resp = _server_request(
                    {"text": text, "output": wav, "lang": lang, "voice": voice},
                    timeout=120, proc=proc)
                if resp and resp.get("ok"):
                    stats = resp.get("stats", {})
                    log(f"kokoro: {stats.get('synth_time', '?')}s synth, "
                        f"{stats.get('duration', '?')}s audio, RTF={stats.get('rtf', '?')}")
                    return True
                err = resp.get("error", "unknown") if resp else "no response"
                log(f"kokoro server synth fail: {err}")
                return False
        kokoro = shutil.which("voice-kokoro")
        if not kokoro:
            log("kokoro: wrapper voice-kokoro no disponible")
            return False
        langc = "en" if lang == "en" else "es"
        return _run([kokoro, "-o", wav, "-l", langc, "-t", text, "-v", voice], None)
    # espeak (final)
    return _run(["espeak-ng", "-v", lang, "-s", "160", "-p", "50", "-w", wav, text], None)


# ── Socket de sintesis a archivo (sin reproducir) ───────────────────────
# Permite que procesos externos (p.ej. OpenClaw talk.speak) pidan TTS a un
# archivo reutilizando el modelo ya cargado en GPU. Protocolo unix socket,
# JSON por linea: {"text","output","lang"?,"engine"?,"voice"?} -> {"ok",...}
def _synth_to_file(req: dict) -> tuple[bool, str]:
    text = (req.get("text") or "").strip()
    output = req.get("output") or ""
    if not text or not output:
        return False, "missing text or output"
    try:
        cfg = load_config()
    except Exception as e:  # config corrupta -> cadena por defecto
        cfg = {"tts": {"lang": "es"}}
    lang = req.get("lang") or cfg["tts"]["lang"]
    try:
        tcfg = tts_command(cfg, lang)
        engine = req.get("engine") or tcfg["engine"]
        voice = req.get("voice") or tcfg["voice"]
    except Exception as e:
        return False, f"config: {e}"

    output = os.path.abspath(os.path.expanduser(output))
    try:
        os.makedirs(os.path.dirname(output) or ".", exist_ok=True)
    except OSError:
        pass

    chain = [engine] + [s for s in ("piper", "espeak") if s != engine]
    for eng in chain:
        if _synth(eng, voice, lang, text, output):
            _apply_effects(output, _as_float(req.get("pitch"), 0.0),
                           _as_float(req.get("speed"), 1.0))
            return True, eng
    return False, "todos los motores fallaron"


def _handle_synth_conn(conn: socket.socket) -> None:
    try:
        conn.settimeout(600)
        buf = b""
        while b"\n" not in buf:
            chunk = conn.recv(65536)
            if not chunk:
                return
            buf += chunk
        line = buf.split(b"\n", 1)[0].decode("utf-8", "replace").strip()
        if not line:
            return
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            _sock_reply(conn, {"ok": False, "error": "invalid JSON"})
            return
        ok, detail = _synth_to_file(req)
        _sock_reply(conn, {"ok": ok, "detail": detail} if ok
                    else {"ok": False, "error": detail})
    except Exception as e:
        try:
            _sock_reply(conn, {"ok": False, "error": str(e)})
        except OSError:
            pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


def _sock_reply(conn: socket.socket, obj: dict) -> None:
    conn.sendall(json.dumps(obj).encode("utf-8") + b"\n")


def serve_synth_socket() -> None:
    try:
        os.makedirs(os.path.dirname(SYNTH_SOCK), exist_ok=True)
        if os.path.exists(SYNTH_SOCK):
            os.remove(SYNTH_SOCK)
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(SYNTH_SOCK)
        os.chmod(SYNTH_SOCK, 0o600)
        srv.listen(8)
    except OSError as e:
        log(f"synth socket no disponible: {e}")
        return
    log(f"synth socket escuchando: {SYNTH_SOCK}")
    while True:
        try:
            conn, _ = srv.accept()
        except OSError as e:
            log(f"synth socket accept error: {e} — saliendo")
            return
        threading.Thread(target=_handle_synth_conn, args=(conn,), daemon=True).start()


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


def _duck_enabled() -> bool:
    """Si pausar la musica/video mientras habla el TTS."""
    try:
        tts = load_config().get("tts", {})
    except Exception:
        return False
    return str(tts.get("duck", True)).strip().lower() not in ("false", "0", "no", "off")


def _players() -> list[str]:
    try:
        r = subprocess.run(["playerctl", "-l"], capture_output=True, text=True, timeout=3)
        return [p.strip() for p in (r.stdout or "").splitlines() if p.strip()]
    except Exception:
        return []


def _player_status(player: str) -> str:
    try:
        r = subprocess.run(["playerctl", "-p", player, "status"],
                           capture_output=True, text=True, timeout=3)
        return (r.stdout or "").strip()
    except Exception:
        return ""


def _pause_players() -> list[str]:
    """Pausa los reproductores que estaban sonando; devuelve cuales pausamos.

    Se pausa la fuente (musica/video) en lugar de bajar el sink: asi la voz
    conserva su volumen y no queda tapada ni opacada por el ducking.
    """
    paused = []
    for p in _players():
        if _player_status(p) == "Playing":
            try:
                subprocess.run(["playerctl", "-p", p, "pause"], capture_output=True, timeout=3)
                paused.append(p)
            except Exception:
                pass
    return paused


def _resume_players(paused: list[str]) -> None:
    for p in paused:
        try:
            subprocess.run(["playerctl", "-p", p, "play"], capture_output=True, timeout=3)
        except Exception:
            pass


def _sink_inputs() -> list[tuple[int, bool]]:
    """(index, muteado) de cada stream de salida (sink-input).

    Sirve para acallar TODO lo que este sonando, incluso lo que playerctl no
    controla (video del navegador, apps sin MPRIS, juegos...).
    """
    try:
        r = subprocess.run(["pactl", "list", "sink-inputs"],
                           capture_output=True, text=True, timeout=5)
    except Exception:
        return []
    items: list[tuple[int, bool]] = []
    idx: int | None = None
    muted = False
    for line in (r.stdout or "").splitlines():
        m = re.match(r"Sink Input #(\d+)", line)
        if m:
            if idx is not None:
                items.append((idx, muted))
            idx, muted = int(m.group(1)), False
        elif idx is not None and re.match(r"\s*Mute:\s*yes", line):
            muted = True
    if idx is not None:
        items.append((idx, muted))
    return items


def _set_stream_mute(index: int, muted: bool) -> None:
    try:
        subprocess.run(["pactl", "set-sink-input-mute", str(index),
                        "1" if muted else "0"], capture_output=True, timeout=3)
    except Exception:
        pass


def _mute_other_streams() -> list[tuple[int, bool]]:
    """Acalla lo que ya estaba sonando; devuelve el estado para restaurar.

    Se hace ANTES de arrancar pw-play, asi el stream de la voz nace sin mutear
    y no hay que identificarlo. Red de seguridad ademas del pause via MPRIS:
    cubre el audio que playerctl no puede pausar (p.ej. video en el navegador).
    """
    saved = _sink_inputs()
    for index, muted in saved:
        if not muted:
            _set_stream_mute(index, True)
    return saved


def _restore_streams(saved: list[tuple[int, bool]]) -> None:
    for index, muted in saved:
        _set_stream_mute(index, muted)


def _wav_duration_ms(wav: str) -> int:
    """Duración del WAV en ms (para sincronizar el resaltado palabra a palabra)."""
    try:
        out = subprocess.run(["soxi", "-D", wav], capture_output=True, text=True, timeout=5).stdout.strip()
        return max(0, int(float(out) * 1000))
    except Exception:
        return 0


def _publish_speaking(text: str, wav: str, source: str, engine: str, voice: str) -> None:
    try:
        payload = {
            "text": text,
            "wav": wav,
            "durationMs": _wav_duration_ms(wav),
            "startedAt": int(time.time() * 1000),
            "source": source or "",
            "engine": engine or "",
            "voice": voice or "",
        }
        tmp = f"{SPEAKING_FILE}.{os.getpid()}"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(payload, fh, ensure_ascii=False)
        os.replace(tmp, SPEAKING_FILE)
    except Exception:
        pass


def _clear_speaking() -> None:
    try:
        os.remove(SPEAKING_FILE)
    except OSError:
        pass


def _play(wav: str, text: str | None = None, source: str = "",
          engine: str = "", voice: str = "") -> bool:
    if not os.path.isfile(wav):
        return False
    # El volumen es un factor relativo sobre el volumen general de salida
    # (pw-play lo aplica sobre el sink): no es un volumen independiente, asi
    # que bajar el general tambien baja la voz.
    try:
        vol = tts_volume()
    except Exception:
        vol = 1.0
    # Nombre propio para el stream de la voz: asi el mute de "lo demás"
    # (module-stream-restore guarda el estado por application.name) nunca
    # deja muda a la propia voz en la proxima reproduccion.
    argv = ["pw-play", "-P", '{ application.name = "Voice TTS" }',
            f"--volume={vol:.3f}", wav]
    # Ducking: mientras habla, pausa la musica/video (MPRIS) y acalla cualquier
    # otro audio que playerctl no maneje; al terminar, restaura todo.
    duck = _duck_enabled()
    paused = _pause_players() if duck else []
    muted = _mute_other_streams() if duck else []
    if duck and (paused or len([m for _, m in muted if not m]) > 0):
        log(f"duck: pausados={paused or '[]'} acallados={len([m for _, m in muted if not m])}")
    published = False
    try:
        # Publicar qué se está diciendo, para que el glow muestre los subtítulos.
        if text:
            _publish_speaking(text, wav, source, engine, voice)
            published = True
        r = subprocess.run(argv, capture_output=True, timeout=900)
        if r.returncode != 0:
            return False
        return True
    except Exception as e:
        log(f"play error: {e}")
        return False
    finally:
        if published:
            _clear_speaking()
        if muted:
            _restore_streams(muted)
        if paused:
            _resume_players(paused)


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
        _shutdown_kokoro_server()
        try:
            if os.path.exists(SYNTH_SOCK):
                os.remove(SYNTH_SOCK)
        except OSError:
            pass
        sys.exit(0)

    def _hup(_s, _f):
        log("SIGHUP — recargando config")
        load_config()

    signal.signal(signal.SIGTERM, _term)
    signal.signal(signal.SIGHUP, _hup)

    log("voice-daemon arrancado")
    ensure_fifo()

    threading.Thread(target=worker, daemon=True).start()
    threading.Thread(target=serve_synth_socket, daemon=True).start()

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