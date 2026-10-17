#!/usr/bin/env python3

import json
import os
import sys
import time
import wave

import numpy as np

_here = os.path.dirname(os.path.abspath(__file__))
sys.path = [p for p in sys.path if os.path.abspath(p or "") != _here] + [_here]

SAMPLE_RATE = 24000
LANG_CODES = {"en": "a", "es": "e"}
DEFAULT_VOICES = {"a": "af_heart", "e": "ef_dora"}

_pipelines = {}


def _pipeline(lang: str):
    from kokoro import KPipeline

    code = LANG_CODES.get(lang, "a")
    if code not in _pipelines:
        started = time.time()
        _pipelines[code] = KPipeline(lang_code=code, repo_id="hexgrad/Kokoro-82M")
        print(f"[kokoro-server] pipeline {code} listo en {time.time() - started:.1f}s", file=sys.stderr)
    return _pipelines[code]


def _synth_chunks(pipeline, text: str, name: str) -> list:
    return [audio for _, _, audio in pipeline(text, voice=name, speed=1.0)]


def synth_to_wav(text: str, output_path: str, lang: str = "es", voice: str = None) -> dict:
    code = LANG_CODES.get(lang, "a")
    pipeline = _pipeline(lang)
    name = voice or DEFAULT_VOICES[code]
    started = time.time()
    try:
        chunks = _synth_chunks(pipeline, text, name)
    except Exception as exc:
        # Voz inexistente (p.ej. un nombre de piper llegó a kokoro): caer a la
        # voz por defecto del idioma en vez de fallar con 404 de HuggingFace.
        fallback = DEFAULT_VOICES[code]
        if name == fallback:
            raise
        print(f"[kokoro-server] voz '{name}' no disponible ({exc}); uso '{fallback}'", file=sys.stderr)
        name = fallback
        chunks = _synth_chunks(pipeline, text, name)
    synth_time = time.time() - started
    samples = np.concatenate(chunks)
    pcm = (samples * 32767).astype(np.int16)
    with wave.open(output_path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(pcm.tobytes())
    duration = len(samples) / SAMPLE_RATE
    return {
        "duration": round(duration, 2),
        "synth_time": round(synth_time, 2),
        "rtf": round(synth_time / duration, 2) if duration > 0 else 0,
        "sample_rate": SAMPLE_RATE,
        "lang": lang,
        "voice": name,
    }


def _respond(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def main() -> None:
    for lang in os.environ.get("KOKORO_PRELOAD", "es").split(","):
        lang = lang.strip()
        if lang:
            _pipeline(lang)
    print("[kokoro-server] Ready", file=sys.stderr)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            _respond({"ok": False, "error": "invalid JSON"})
            continue
        if req.get("ping"):
            _respond({"pong": True})
            continue
        if req.get("shutdown"):
            _respond({"ok": True, "msg": "shutting down"})
            break
        text = str(req.get("text", "")).strip()
        output = str(req.get("output", ""))
        if not text or not output:
            _respond({"ok": False, "error": "missing text or output"})
            continue
        try:
            stats = synth_to_wav(text, output, lang=req.get("lang", "es"), voice=req.get("voice"))
            _respond({"ok": True, "stats": stats})
        except Exception as exc:
            _respond({"ok": False, "error": str(exc)})


if __name__ == "__main__":
    main()
