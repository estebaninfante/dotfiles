#!/usr/bin/env python3
"""El único Kokoro del sistema: un proceso, un modelo, todos los clientes.

Antes había tres servidores Kokoro a la vez —el de Orión (asistente-voz.sock),
el de Read Aloud de Zotero (kokoro-tts.sock) y el que el daemon de voz arrancaba
por stdin— cada uno con su copia del modelo en memoria. Este archivo los
reemplaza a todos: escucha los dos sockets que ya usaban los clientes, entiende
las dos formas de pedir (claves en español de Orión, en inglés del lector) y
devuelve siempre el mismo formato. Un solo modelo cargado, en GPU si hay.

Contrato — una petición por conexión, respuesta en tramas:

    petición:  {"texto"|"text": ..., "voz"|"voice": ...,
                "velocidad"|"speed": ..., "rate": ..., "volumen"|"volume": ...}
    respuesta: [uint32 BE largo][PCM s16le 24 kHz mono] ... [uint32 BE 0]

La voz elige el idioma: `ef_`/`em_` → español, el resto → inglés. Sin voz manda
el socket: asistente-voz.sock contesta en español (ef_dora, la voz de Orión) y
kokoro-tts.sock en inglés (am_liam, la que espera Read Aloud). Si el cliente
cierra la conexión se deja de sintetizar (así se corta la frase en curso).

Se queda caliente: Orión responde por voz y un modelo frío tarda segundos en la
primera frase. KOKORO_IDLE_S=<segundos> lo descarga tras ese rato sin pedidos.

Variables:
  KOKORO_SOCKETS   sockets a servir (separados por coma); default los dos de siempre
  KOKORO_IDLE_S    segundos sin uso antes de soltar el modelo (0 = nunca; default 0)
  KOKORO_DEVICE    cuda | cpu (default: cuda si hay)
  KOKORO_WARM      idiomas a precargar (default "e"; vacío = ninguno)
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
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

import numpy as np

RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/kokoro-{os.getuid()}"
DEFAULT_SOCKETS = ["kokoro-tts.sock", "asistente-voz.sock"]
SOCKETS = [
    os.path.join(RUNTIME, name.strip())
    for name in (os.environ.get("KOKORO_SOCKETS") or ",".join(DEFAULT_SOCKETS)).split(",")
    if name.strip()
]
SAMPLE_RATE = 24000
MAX_REQUEST = 8 * 1024 * 1024
IDLE_S = float(os.environ.get("KOKORO_IDLE_S") or 0)
WARM = [lang.strip() for lang in (os.environ.get("KOKORO_WARM", "e")).split(",") if lang.strip()]

# Voz por defecto de cada socket: la que espera su cliente de siempre.
DEFAULT_VOICE = {
    "kokoro-tts.sock": "am_liam",
    "asistente-voz.sock": "ef_dora",
}
FALLBACK_VOICE = {"e": "ef_dora", "a": "am_liam"}

# Nombres cortos que usan speech-dispatcher y el lector de Zotero.
VOICE_MAP = {
    "liam": "am_liam", "male1": "am_liam",
    "puck": "am_puck", "male2": "am_puck",
    "fable": "bm_fable", "male3": "bm_fable",
    "heart": "af_heart", "female1": "af_heart",
    "bella": "af_bella", "nicole": "af_nicole", "emma": "bf_emma",
    "dora": "ef_dora", "alex": "em_alex", "santa": "em_santa",
}

_model = None
_pipelines: dict[str, object] = {}
_pipeline_lock = threading.Lock()
_synth_lock = threading.Lock()
_last_use = time.monotonic()


def log(*args) -> None:
    print("kokoro-server:", *args, file=sys.stderr, flush=True)


def _device() -> str:
    chosen = (os.environ.get("KOKORO_DEVICE") or "").strip().lower()
    if chosen in ("cuda", "cpu"):
        return chosen
    try:
        import torch

        if torch.cuda.is_available():
            return "cuda"
    except Exception:
        pass
    return "cpu"


def _load_model():
    """Carga el modelo una vez; los idiomas comparten los mismos pesos."""
    global _model
    if _model is not None:
        return _model
    from kokoro import KModel

    device = _device()
    log(f"cargando modelo en {device}")
    started = time.time()
    try:
        _model = KModel(repo_id="hexgrad/Kokoro-82M").to(device).eval()
    except Exception as exc:  # noqa: BLE001 - sin GPU se habla igual, más lento
        if device == "cpu":
            raise
        log(f"GPU no disponible ({exc}); sigo en CPU")
        _model = KModel(repo_id="hexgrad/Kokoro-82M").to("cpu").eval()
        device = "cpu"
    log(f"modelo listo en {time.time() - started:.1f}s ({device})")
    return _model


def pipeline(lang: str):
    code = lang if lang in ("a", "e") else "a"
    with _pipeline_lock:
        if code not in _pipelines:
            from kokoro import KPipeline

            started = time.time()
            _pipelines[code] = KPipeline(
                lang_code=code, repo_id="hexgrad/Kokoro-82M", model=_load_model()
            )
            log(f"pipeline {'es' if code == 'e' else 'en'} listo en {time.time() - started:.1f}s")
        return _pipelines[code]


def release_model() -> None:
    global _model
    if _model is None:
        return
    with _pipeline_lock:
        _pipelines.clear()
        _model = None
    gc.collect()
    try:
        import ctypes

        ctypes.CDLL("libc.so.6").malloc_trim(0)
    except Exception:
        pass
    log("modelo liberado tras inactividad")


def watchdog() -> None:
    if IDLE_S <= 0:
        return
    while True:
        time.sleep(30)
        if _model is None or time.monotonic() - _last_use < IDLE_S:
            continue
        if _synth_lock.acquire(blocking=False):
            try:
                if _model is not None and time.monotonic() - _last_use >= IDLE_S:
                    release_model()
            finally:
                _synth_lock.release()


def lang_of(voice: str) -> str:
    return "e" if voice.startswith("e") else "a"


def resolve_voice(name: str, default: str) -> str:
    key = (name or "").strip().lower()
    if not key:
        return default
    alias = VOICE_MAP.get(key)
    if alias:
        return alias
    if len(key) >= 3 and key[2] == "_":
        # Nombre completo de Kokoro (af_heart, ef_dora, bm_fable...).
        return key
    return VOICE_MAP.get(key.split()[-1], default)


def speed_of(pet: dict) -> float:
    """`velocidad`/`speed` es un factor; `rate` es el porcentaje del lector."""
    if "velocidad" in pet or "speed" in pet:
        try:
            speed = float(pet.get("velocidad", pet.get("speed")))
        except (TypeError, ValueError):
            speed = 1.0
    elif pet.get("rate") is not None:
        try:
            rate = float(pet.get("rate"))
        except (TypeError, ValueError):
            rate = 0.0
        speed = 2.5 ** (rate / 100.0) if rate > 0 else 0.5 ** (-rate / 100.0) if rate < 0 else 1.0
    else:
        speed = 1.0
    return max(0.5, min(2.0, speed))


def volume_of(pet: dict) -> float:
    try:
        return max(0.0, min(2.0, float(pet.get("volumen", pet.get("volume", 100))) / 100.0))
    except (TypeError, ValueError):
        return 1.0


def _pcm(audio, volume: float) -> bytes:
    samples = np.asarray(getattr(audio, "numpy", lambda: audio)(), dtype=np.float32)
    if volume != 1.0:
        samples = samples * volume
    return (np.clip(samples, -1.0, 1.0) * 32767.0).astype(np.int16).tobytes()


def synth(req: dict, default_voice: str):
    """Genera PCM s16le 24 kHz mono trozo a trozo (streaming)."""
    text = (req.get("texto") or req.get("text") or "").strip()
    if not text:
        return
    voice = resolve_voice(req.get("voz") or req.get("voice") or "", default_voice)
    code = lang_of(voice)
    speed = speed_of(req)
    volume = volume_of(req)
    pipe = pipeline(code)
    try:
        for _gs, _ps, audio in pipe(text, voice=voice, speed=speed):
            if audio is not None:
                yield _pcm(audio, volume)
    except Exception as exc:  # noqa: BLE001 - voz inexistente: usar la del idioma
        fallback = FALLBACK_VOICE[code]
        if voice == fallback:
            raise
        log(f"voz '{voice}' no disponible ({exc}); uso '{fallback}'")
        for _gs, _ps, audio in pipe(text, voice=fallback, speed=speed):
            if audio is not None:
                yield _pcm(audio, volume)


def handle(conn: socket.socket, default_voice: str) -> None:
    global _last_use
    try:
        buf = b""
        while b"\n" not in buf:
            chunk = conn.recv(65536)
            if not chunk:
                return
            buf += chunk
            if len(buf) > MAX_REQUEST:
                return
        req = json.loads(buf.split(b"\n", 1)[0].decode("utf-8", "replace") or b"{}")
        if req.get("ping"):
            conn.sendall(struct.pack(">I", 0))
            return
        text = (req.get("texto") or req.get("text") or "").strip()
        log(f"synth voz={resolve_voice(req.get('voz') or req.get('voice') or '', default_voice)} "
            f"caracteres={len(text)}")
        if text:
            with _synth_lock:
                _last_use = time.monotonic()
                for pcm in synth(req, default_voice):
                    conn.sendall(struct.pack(">I", len(pcm)) + pcm)
                _last_use = time.monotonic()
        conn.sendall(struct.pack(">I", 0))
    except (BrokenPipeError, ConnectionResetError):
        pass  # lo cortaron a mitad de frase: se deja de sintetizar
    except Exception as exc:  # noqa: BLE001
        log(f"error: {exc}")
        try:
            conn.sendall(struct.pack(">I", 0))
        except OSError:
            pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


def _owned_by_other(path: str) -> bool:
    """¿Otro servidor ya está escuchando ahí? (antes de robarle el socket)."""
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        probe.settimeout(0.5)
        probe.connect(path)
        return True
    except OSError:
        return False
    finally:
        probe.close()


def listen(path: str) -> socket.socket | None:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    if os.path.exists(path):
        if _owned_by_other(path):
            log(f"{os.path.basename(path)} lo sirve otro proceso; no lo toco")
            return None
        try:
            os.unlink(path)
        except OSError:
            pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(path)
    os.chmod(path, 0o600)
    srv.listen(16)
    return srv


def _serve(srv: socket.socket, default_voice: str) -> None:
    while True:
        try:
            conn, _ = srv.accept()
        except OSError as exc:
            if exc.errno == errno.EINTR:
                continue
            raise
        threading.Thread(target=handle, args=(conn, default_voice), daemon=True).start()


def main() -> int:
    lock_fd = open(os.path.join(RUNTIME, "kokoro-tts.server.lock"), "w")
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        log("ya hay un kokoro-server activo; salgo")
        return 0

    if WARM:
        log(f"precalentando {'/'.join(WARM)}")
        pipeline(WARM[0])

    servers = []
    for path in SOCKETS:
        srv = listen(path)
        if srv is not None:
            servers.append((srv, path))
            log(f"escuchando en {path}")
    if not servers:
        log("ningún socket disponible; salgo")
        return 1

    threading.Thread(target=watchdog, daemon=True).start()
    for srv, path in servers:
        name = os.path.basename(path)
        threading.Thread(
            target=_serve, args=(srv, DEFAULT_VOICE.get(name, "ef_dora")), daemon=True
        ).start()

    while True:
        time.sleep(3600)


if __name__ == "__main__":
    sys.exit(main())
