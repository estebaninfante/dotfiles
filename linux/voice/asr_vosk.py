#!/usr/bin/env python3
# asr_vosk.py — streaming ASR con Vosk (CPU) para el wake-word de talk-command.
#
# Lee PCM s16le mono (16 kHz por defecto) por stdin y escribe UNA linea JSON por
# segmento final reconocido:
#     {"text": "dime", "final": true}
#
# Es la pata CPU del selector `voice-asr-stream` (la GPU, si esta configurada,
# la usa `[wake] gpu_command`). Vosk es liviano y no toca la VRAM que ya usan
# los motores TTS; por eso es un buen respaldo/opcion en laptop.

from __future__ import annotations

import argparse
import json
import sys

READ_CHUNK = 4000  # bytes: ~125 ms a 16 kHz s16le


def emit(text: str) -> None:
    text = (text or "").strip()
    if not text:
        return
    sys.stdout.write(json.dumps({"text": text, "final": True}, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main() -> int:
    ap = argparse.ArgumentParser(description="Vosk streaming a stdout (jsonl).")
    ap.add_argument("-m", "--model", required=True, help="ruta del modelo Vosk")
    ap.add_argument("--sample-rate", type=int, default=16000)
    args = ap.parse_args()

    from vosk import Model, KaldiRecognizer, SetLogLevel

    SetLogLevel(-1)
    model = Model(args.model)
    rec = KaldiRecognizer(model, args.sample_rate)

    while True:
        chunk = sys.stdin.buffer.read(READ_CHUNK)
        if not chunk:
            break
        if rec.AcceptWaveform(chunk):
            try:
                emit(json.loads(rec.Result()).get("text", ""))
            except Exception:
                pass

    try:
        emit(json.loads(rec.FinalResult()).get("text", ""))
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
