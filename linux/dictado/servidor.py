#!/usr/bin/env python3
"""Servidor STT local para `dictado` — faster-whisper, sin dependencias de Omar.

Carga UN modelo una vez (GPU por defecto, CPU si no hay CUDA) y transcribe
audio crudo. Lo usa `~/.local/bin/dictado` al cerrar cada dictado; también se
puede probar a mano:

    curl --data-binary @audio.f32 'http://127.0.0.1:8091/transcribir?idioma=es'

Entradas:
  POST /transcribir?idioma=es&formato=raw|wav[&prompt=vocabulario]
       raw  (por defecto): float32 little-endian, mono, 16 kHz, sin cabecera.
       wav              : archivo WAV mono 16 kHz.
       -> {"texto": str, "idioma": str, "segundos": float}
  GET  /salud  -> {"ok": true, "modelo": str, ...}

Variables:
  DICTADO_MODELO    repo/id de faster-whisper (default: mobiuslabsgmbh/faster-whisper-large-v3-turbo)
  DICTADO_MODELOS   caché local de modelos (default: ~/.local/share/dictado/models)
  DICTADO_PUERTO    puerto (default: 8091)
  DICTADO_IDIOMA    idioma por defecto (default: es)
  DICTADO_PROMPT    sesgo de vocabulario para el decodificador (opcional)
  DICTADO_DISPOSITIVO / DICTADO_COMPUTO  cuda+int8_float16 por defecto; si falla, cpu+int8
"""

from __future__ import annotations

import io
import json
import os
import re
import subprocess
import sys
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOME = os.path.expanduser("~")


import numpy as np  # noqa: E402
from faster_whisper import WhisperModel  # noqa: E402

MODELO = os.environ.get("DICTADO_MODELO", "mobiuslabsgmbh/faster-whisper-large-v3-turbo")
MODELO_RAPIDO = os.environ.get("DICTADO_MODELO_RAPIDO", "Systran/faster-whisper-small")
MODELOS = os.environ.get("DICTADO_MODELOS") or os.path.join(HOME, ".local/share/dictado/models")
PUERTO = int(os.environ.get("DICTADO_PUERTO", "8091"))
IDIOMA = os.environ.get("DICTADO_IDIOMA", "es")
PROMPT = os.environ.get("DICTADO_PROMPT") or None
DISPOSITIVO = os.environ.get("DICTADO_DISPOSITIVO", "cuda")
COMPUTO = os.environ.get("DICTADO_COMPUTO", "int8_float16")
HILOS = int(os.environ.get("DICTADO_HILOS", "0")) or min(8, os.cpu_count() or 4)
# VRAM que hace falta (MiB) para que el modelo grande entre sin desalojar lo que
# ya está usando la GPU (por ejemplo el visor de video).
VRAM_PRECISO = int(os.environ.get("DICTADO_VRAM_PRECISO_MB", "2400"))
VRAM_RAPIDO = int(os.environ.get("DICTADO_VRAM_RAPIDO_MB", "1100"))
MAX_BYTES = 64 * 1024 * 1024  # 16 minutos de float32 a 16 kHz
SAMPLE_RATE = 16000

# Frases que Whisper inventa sobre silencio o ruido. Sólo se descartan en clips
# cortos y cuando el propio modelo suena inseguro: un "gracias" real dentro de
# una frase larga tiene que seguir escribiéndose.
SOSPECHOSAS = {
    "gracias",
    "muchas gracias",
    "gracias por ver el video",
    "gracias por ver el vídeo",
    "gracias por ver este video",
    "subtitulos realizados por la comunidad de amara org",
    "subtítulos realizados por la comunidad de amara org",
    "thank you",
    "thank you very much",
    "thanks for watching",
    "thank you for watching",
    "aplausos",
    "música",
    "musica",
}

_lock = threading.Lock()
_modelo: WhisperModel | None = None
_modelo_real = ""
_dispositivo_real = "?"
_error_carga = ""
# Motor rápido (small): transcribe los subtítulos en vivo mientras hablás, sin
# pelear por el lock del modelo grande. Se carga sólo cuando se pide.
_lock_rapido = threading.Lock()
_rapido: WhisperModel | None = None
_rapido_error = ""


def log(msg: str) -> None:
    print(f"[dictado] {msg}", file=sys.stderr, flush=True)


def vram_libre_mb() -> int | None:
    """VRAM libre según nvidia-smi, o None si no hay GPU/nvidia-smi."""
    try:
        salida = subprocess.run(
            ["nvidia-smi", "--query-gpu=memory.free", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=3, check=True).stdout
        return min(int(l.strip()) for l in salida.splitlines() if l.strip())
    except Exception:  # noqa: BLE001 — sin GPU simplemente se usa CPU
        return None


def _intentos() -> list[tuple[str, str, str]]:
    """(modelo, dispositivo, cómputo) en orden de preferencia, según la VRAM.

    Preferir el modelo grande en GPU cuando entra, y si la GPU está ocupada por
    otra cosa (visor de video, ollama) usar el chico en GPU o, si tampoco entra,
    en CPU: dictar no puede depender de tener la placa libre.
    """
    if DISPOSITIVO == "cpu":
        return [(MODELO, "cpu", "int8"), (MODELO_RAPIDO, "cpu", "int8")]
    libre = vram_libre_mb()
    intentos: list[tuple[str, str, str]] = []
    if libre is None or libre >= VRAM_PRECISO:
        intentos.append((MODELO, "cuda", COMPUTO))
    if libre is None or libre >= VRAM_RAPIDO:
        intentos.append((MODELO_RAPIDO, "cuda", COMPUTO))
    intentos += [(MODELO_RAPIDO, "cpu", "int8"), (MODELO, "cpu", "int8")]
    return intentos


def cargar_modelo() -> WhisperModel:
    """Carga el modelo una vez, degradando si la GPU no tiene lugar."""
    global _modelo, _modelo_real, _dispositivo_real, _error_carga
    with _lock:
        if _modelo is not None:
            return _modelo
        os.makedirs(MODELOS, exist_ok=True)
        for modelo, dispositivo, computo in _intentos():
            try:
                t0 = time.time()
                _modelo = WhisperModel(
                    modelo,
                    device=dispositivo,
                    compute_type=computo,
                    download_root=MODELOS,
                    cpu_threads=HILOS,
                    num_workers=1,
                )
                _modelo_real = modelo
                _dispositivo_real = f"{dispositivo}/{computo}"
                log(f"modelo {modelo} cargado en {_dispositivo_real} ({time.time() - t0:.1f}s)")
                return _modelo
            except Exception as exc:  # noqa: BLE001 — se prueba el siguiente candidato
                _error_carga = f"{modelo} {dispositivo}/{computo}: {exc}"
                log(f"no pude cargar {modelo} en {dispositivo}/{computo}: {exc}")
        raise RuntimeError(f"no pude cargar ningún modelo de voz ({_error_carga})")


def cargar_rapido() -> WhisperModel:
    """Modelo chico para subtítulos en vivo; si no entra en la GPU, va a CPU."""
    global _rapido, _rapido_error
    with _lock_rapido:
        if _rapido is not None:
            return _rapido
        if _modelo_real == MODELO_RAPIDO and _modelo is not None:
            _rapido = _modelo
            return _rapido
        libre = vram_libre_mb()
        intentos = []
        if DISPOSITIVO != "cpu" and (libre is None or libre >= VRAM_RAPIDO):
            intentos.append(("cuda", COMPUTO))
        intentos.append(("cpu", "int8"))
        for dispositivo, computo in intentos:
            try:
                t0 = time.time()
                _rapido = WhisperModel(
                    MODELO_RAPIDO, device=dispositivo, compute_type=computo,
                    download_root=MODELOS, cpu_threads=HILOS, num_workers=1,
                )
                log(f"modelo rápido cargado en {dispositivo}/{computo} ({time.time() - t0:.1f}s)")
                return _rapido
            except Exception as exc:  # noqa: BLE001
                _rapido_error = f"{dispositivo}/{computo}: {exc}"
                log(f"no pude cargar el modelo rápido en {dispositivo}/{computo}: {exc}")
        raise RuntimeError(f"no pude cargar el modelo rápido ({_rapido_error})")


def normalizar(texto: str) -> str:
    texto = texto.lower().strip()
    texto = re.sub(r"[\.,!¡¿?;:]+", " ", texto)
    return re.sub(r"\s+", " ", texto).strip()


def es_ruido(texto: str) -> bool:
    """Texto repetido tipo "no no no no" o la misma palabra en bucle."""
    palabras = normalizar(texto).split()
    if len(palabras) < 5:
        return False
    return len(set(palabras)) * 3 <= len(palabras)


def wav_a_pcm(datos: bytes) -> np.ndarray:
    with wave.open(io.BytesIO(datos), "rb") as w:
        if w.getnchannels() != 1:
            raise ValueError("el WAV debe ser mono")
        ancho = w.getsampwidth()
        if ancho not in (2, 4):
            raise ValueError("el WAV debe ser float32 o PCM de 16 bits")
        tasa = w.getframerate()
        crudo = w.readframes(w.getnframes())
    pcm = np.frombuffer(crudo, dtype="<f4" if ancho == 4 else "<i2").astype(np.float32)
    if ancho == 2:
        pcm /= 32768.0
    if tasa != SAMPLE_RATE:
        pcm = remuestrear(pcm, tasa, SAMPLE_RATE)
    return pcm


def remuestrear(pcm: np.ndarray, origen: int, destino: int) -> np.ndarray:
    if origen == destino or pcm.size == 0:
        return pcm
    salida = int(round(pcm.size * destino / origen))
    return np.interp(
        np.linspace(0.0, pcm.size - 1, salida, dtype=np.float64),
        np.arange(pcm.size, dtype=np.float64),
        pcm,
    ).astype(np.float32)


def transcribir(pcm: np.ndarray, idioma: str, rapido: bool = False, prompt: str | None = None,
                vad: bool = True, filtrar: bool = True) -> dict:
    if pcm.size < SAMPLE_RATE // 4:
        return {"texto": "", "idioma": idioma, "motivo": "audio muy corto"}
    pico = float(np.abs(pcm).max()) if pcm.size else 0.0
    if pico < 0.002:  # silencio digital
        return {"texto": "", "idioma": idioma, "motivo": "silencio"}
    modelo = cargar_rapido() if rapido else cargar_modelo()
    cerrojo = _lock_rapido if rapido else _lock
    t0 = time.time()
    with cerrojo:
        segmentos, info = modelo.transcribe(
            pcm,
            language=None if idioma == "auto" else idioma,
            beam_size=1,
            # Con `vad=False` no se filtra el audio: las palabras clave cortas
            # ("grilla", "dicta", "Orión") desaparecían al pasar por Silero.
            vad_filter=vad,
            vad_parameters={"min_silence_duration_ms": 400},
            initial_prompt=prompt or PROMPT,
            condition_on_previous_text=False,
        )
        textos = [s.text.strip() for s in segmentos]
        logprobs = [s.avg_logprob for s in segmentos if s.avg_logprob is not None]
        sin_voz = [s.no_speech_prob for s in segmentos if s.no_speech_prob is not None]
    texto = re.sub(r"\s+", " ", " ".join(t for t in textos if t)).strip()
    segundos = float(info.duration or 0.0)
    inseguro = bool(logprobs) and sum(logprobs) / len(logprobs) < -0.5
    inseguro = inseguro or (bool(sin_voz) and sum(sin_voz) / len(sin_voz) >= 0.5)
    if filtrar and normalizar(texto) in SOSPECHOSAS and (segundos <= 3.0 or inseguro):
        texto = ""
    if filtrar and es_ruido(texto):
        texto = ""
    return {
        "texto": texto,
        "idioma": getattr(info, "language", None) or idioma,
        "segundos": round(time.time() - t0, 2),
        "audio": round(segundos, 2),
    }


def salud() -> dict:
    return {
        "ok": _modelo is not None,
        "modelo": _modelo_real or MODELO,
        "dispositivo": _dispositivo_real,
        "rapido": (MODELO_RAPIDO if _rapido is None else getattr(_rapido, "model_id", MODELO_RAPIDO)),
        "error": _error_carga if _modelo is None else "",
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "dictado/1"

    def log_message(self, formato: str, *args) -> None:  # noqa: D401 — firma de BaseHTTPRequestHandler
        log(formato % args)

    def _json(self, datos: dict, codigo: int = 200) -> None:
        cuerpo = json.dumps(datos).encode()
        self.send_response(codigo)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(cuerpo)))
        self.end_headers()
        self.wfile.write(cuerpo)

    def do_GET(self) -> None:  # noqa: N802 — nombre que espera http.server
        ruta = urlparse(self.path).path
        if ruta in ("/salud", "/health"):
            self._json(salud())
            return
        self._json({"error": "ruta desconocida"}, 404)

    def do_POST(self) -> None:  # noqa: N802
        url = urlparse(self.path)
        if url.path not in ("/transcribir", "/transcribe"):
            self._json({"error": "ruta desconocida"}, 404)
            return
        try:
            largo = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            largo = 0
        if largo <= 0:
            self._json({"error": "cuerpo vacío"}, 400)
            return
        if largo > MAX_BYTES:
            self._json({"error": "audio demasiado largo"}, 413)
            return
        cuerpo = self.rfile.read(largo)
        consulta = parse_qs(url.query)
        # /transcribe es el contrato del oído del asistente (f32 crudo + "language");
        # /transcribir el de `dictado` (raw/wav + "idioma"). Mismo motor, dos nombres.
        idioma = (consulta.get("idioma") or consulta.get("language") or [IDIOMA])[0] or IDIOMA
        formato = (consulta.get("formato") or ["raw"])[0].lower()
        rapido = (consulta.get("rapido") or ["0"])[0] in ("1", "true", "si", "sí")
        prompt = (consulta.get("prompt") or [""])[0] or None  # vocabulario del cliente (p. ej. Estudio)
        # El oído del asistente ya trae el audio cortado por su VAD y necesita las
        # palabras sueltas ("grilla", "dicta", "Orión"): para /transcribe no se filtra
        # salvo que lo pidan explícitamente. `dictado` conserva los filtros de antes.
        por_defecto = "0" if url.path == "/transcribe" else "1"
        vad = (consulta.get("vad") or [por_defecto])[0] not in ("0", "false", "no")
        filtrar = (consulta.get("filtrar") or [por_defecto])[0] not in ("0", "false", "no")
        try:
            pcm = wav_a_pcm(cuerpo) if formato == "wav" else np.frombuffer(cuerpo, dtype="<f4").copy()
        except Exception as exc:  # noqa: BLE001 — se informa al cliente
            self._json({"error": f"audio inválido: {exc}"}, 400)
            return
        try:
            resultado = transcribir(pcm, idioma, rapido, prompt, vad=vad, filtrar=filtrar)
            if url.path == "/transcribe":
                # el oído del asistente lee la clave "text"
                resultado = {**resultado, "text": resultado.get("texto", "")}
            self._json(resultado)
        except Exception as exc:  # noqa: BLE001
            log(f"error transcribiendo: {exc}")
            self._json({"error": str(exc)}, 500)


def main(argv: list[str]) -> int:
    if "--cargar" in argv:  # precarga el modelo y sale (smoke test)
        cargar_modelo()
        print(json.dumps(salud()))
        return 0
    # Sin precarga: en reposo el servidor no ocupa VRAM ni RAM de modelo.
    # `transcribir()` carga el modelo bajo lock en el primer dictado.
    servidor = ThreadingHTTPServer(("127.0.0.1", PUERTO), Handler)
    log(f"escuchando en 127.0.0.1:{PUERTO} · {MODELO} ({DISPOSITIVO}/{COMPUTO}) se carga al primer dictado · modelos en {MODELOS}")
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
