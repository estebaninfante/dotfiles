#!/usr/bin/env python3
"""Servidor local de síntesis Kokoro para speech-dispatcher / Zotero Read Aloud.

Carga el modelo en el primer pedido y lo libera tras un rato sin uso
(KOKORO_IDLE_S, 900 s por defecto), así en reposo no ocupa RAM. Protocolo:

  petición:  una línea JSON  {"text": ..., "voice": ..., "rate": %, "volume": 0-100}
  respuesta: tramas [uint32 BE: largo][PCM s16le 24000 Hz mono] y una trama
             final de largo 0.
"""
import errno
import fcntl
import gc
import json
import os
import socket
import struct
import sys
import threading
import time
import warnings

warnings.filterwarnings("ignore")
os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/kokoro-{os.getuid()}"
SOCKET_PATH = os.path.join(RUNTIME, "kokoro-tts.sock")
SERVER_LOCK = os.path.join(RUNTIME, "kokoro-tts.server.lock")
SAMPLE_RATE = 24000
MAX_REQUEST = 8 * 1024 * 1024

VOICE_MAP = {
    "liam": "am_liam", "male1": "am_liam",
    "puck": "am_puck", "male2": "am_puck",
    "fable": "bm_fable", "male3": "bm_fable",
    "heart": "af_heart", "female1": "af_heart",
}

pipeline = None
synth_lock = threading.Lock()
last_use = time.monotonic()
IDLE_S = float(os.environ.get("KOKORO_IDLE_S") or 900)


def log(*args):
    print("kokoro-server:", *args, file=sys.stderr, flush=True)


def cargar_modelo():
    """Carga perezosa: sólo cuando alguien pide sintetizar."""
    global pipeline
    if pipeline is None:
        from kokoro import KPipeline
        pipeline = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M")
    return pipeline


def liberar_modelo():
    global pipeline
    if pipeline is None:
        return
    pipeline = None
    gc.collect()
    try:
        import ctypes
        ctypes.CDLL("libc.so.6").malloc_trim(0)
    except Exception:
        pass
    log("modelo liberado tras inactividad")


def vigilante():
    """Suelta el modelo cuando pasó KOKORO_IDLE_S sin pedidos."""
    while True:
        time.sleep(30)
        if pipeline is None or time.monotonic() - last_use < IDLE_S:
            continue
        if synth_lock.acquire(blocking=False):
            try:
                if pipeline is not None and time.monotonic() - last_use >= IDLE_S:
                    liberar_modelo()
            finally:
                synth_lock.release()


def resolve_voice(name: str) -> str:
    key = (name or "").strip().lower()
    if key in VOICE_MAP:
        return VOICE_MAP[key]
    return VOICE_MAP.get(key.split()[-1] if key else "", "am_liam")


def speed_for_rate(rate: float) -> float:
    if rate > 0:
        speed = 2.5 ** (rate / 100.0)
    elif rate < 0:
        speed = 0.5 ** (-rate / 100.0)
    else:
        speed = 1.0
    return max(0.6, min(1.6, speed))


def synthesize(text: str, voice: str, speed: float, volume: float):
    import numpy as np

    for _gs, _ps, audio in pipeline(text, voice=voice, speed=speed):
        a = np.asarray(getattr(audio, "numpy", lambda: audio)(), dtype=np.float32)
        if volume != 1.0:
            a = a * volume
        pcm = (np.clip(a, -1.0, 1.0) * 32767.0).astype(np.int16).tobytes()
        if pcm:
            yield pcm


def handle(conn: socket.socket):
    global last_use
    try:
        buf = b""
        while b"\n" not in buf:
            chunk = conn.recv(65536)
            if not chunk:
                return
            buf += chunk
            if len(buf) > MAX_REQUEST:
                return
        line = buf.split(b"\n", 1)[0]
        req = json.loads(line.decode("utf-8", "replace"))
        text = (req.get("text") or "").strip()
        voice = resolve_voice(req.get("voice") or "")
        speed = speed_for_rate(float(req.get("rate") or 0.0))
        volume = max(0.0, min(2.0, float(req.get("volume") or 100.0) / 100.0))
        log(f"synth voz={voice} velocidad={speed:.2f} caracteres={len(text)}")
        if text:
            with synth_lock:
                last_use = time.monotonic()
                try:
                    cargar_modelo()
                except Exception as exc:  # noqa: BLE001
                    log(f"no pude cargar el modelo: {exc}")
                    conn.sendall(struct.pack(">I", 0))
                    return
                for pcm in synthesize(text, voice, speed, volume):
                    conn.sendall(struct.pack(">I", len(pcm)) + pcm)
                last_use = time.monotonic()
        conn.sendall(struct.pack(">I", 0))
    except (BrokenPipeError, ConnectionResetError, OSError):
        pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


def main():
    global pipeline

    os.makedirs(RUNTIME, exist_ok=True)
    lock_fd = open(SERVER_LOCK, "w")
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log("ya hay un servidor activo; salgo")
        return

    if os.path.exists(SOCKET_PATH):
        probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            probe.connect(SOCKET_PATH)
            probe.close()
            log("socket vivo; salgo")
            return
        except OSError:
            os.unlink(SOCKET_PATH)

    threading.Thread(target=vigilante, daemon=True).start()

    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCKET_PATH)
    os.chmod(SOCKET_PATH, 0o600)
    srv.listen(16)
    log(f"escuchando en {SOCKET_PATH} · modelo perezoso, se libera tras {IDLE_S:.0f}s sin uso")

    while True:
        try:
            conn, _ = srv.accept()
        except OSError as exc:
            if exc.errno == errno.EINTR:
                continue
            raise
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    main()
