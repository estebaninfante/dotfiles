#!/usr/bin/env python3
# stt.py — Speech-to-Text local via faster-whisper.
#
# Uso (interno, via el CLI voice):
#   stt.py transcribe <wav> [--model small] [--backend cpu|cuda] [--lang es]
#   stt.py fetch <model> [--backend cpu|cuda]      # predescarga el modelo
#   stt.py models                                   # modelos locales
#
# Backend:
#   - cpu  → compute_type int8 (CT2). Reproducible y bajo consumo.
#   - cuda → compute_type float16 + device 0 (requiere env faster-whisper
#            con ctranslate2 com CUDA; paquete voice-stt-cuda).
#
# Modelos auto-descargados a ~/.local/share/voice/models (HF download_root)
# en el primer uso. Tras el download inicial el sistema queda 100% offline.

import argparse
import os
import sys

import faster_whisper

from engine import MODEL_DIR, detect, load_config

LANG_MAP = {"es": "es", "en": "en"}


def resolve() -> dict:
    cfg = load_config()
    stt = cfg.get("stt", {})
    return {
        "model": stt.get("model", "small"),
        "backend": stt.get("backend", "cpu"),
        "lang": stt.get("lang", "es"),
    }


def whisper_model(model: str, backend: str):
    """Instancia e incializa el modelo; descarga si falta."""
    if backend == "cuda" and not os.path.exists("/dev/nvidia0"):
        print("stt: no hay GPU NVIDIA, uso CPU", file=sys.stderr)
        backend = "cpu"
    if backend == "cuda":
        device = "cuda"
        compute = "float16"
    else:
        device = "cpu"
        compute = "int8"
    os.makedirs(MODEL_DIR, exist_ok=True)
    return faster_whisper.WhisperModel(
        model,
        device=device,
        compute_type=compute,
        download_root=MODEL_DIR,
    )


def transcribe(wav: str, model: str, backend: str, lang: str) -> str:
    if not os.path.isfile(wav):
        raise SystemExit(f"stt: no encuentro '{wav}'")
    m = whisper_model(model, backend)
    segments, _info = m.transcribe(
        wav,
        language=lang,
        beam_size=1,
        vad_filter=True,
        vad_parameters={"min_silence_duration_ms": 300},
        condition_on_previous_text=False,
    )
    text = " ".join(seg.text.strip() for seg in segments).strip()
    return text


def fetch(model: str, backend: str) -> None:
    print(f"stt: descargando modelo '{model}' (backend {backend}, dir {MODEL_DIR})")
    whisper_model(model, backend)
    print("stt: listo")


def main() -> None:
    ap = argparse.ArgumentParser(prog="stt")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("transcribe")
    p.add_argument("wav")
    p.add_argument("--model", default=None)
    p.add_argument("--backend", default=None)
    p.add_argument("--lang", default=None)

    p = sub.add_parser("fetch")
    p.add_argument("model")
    p.add_argument("--backend", default=None)

    sub.add_parser("models")

    args = ap.parse_args()
    cfg = load_config()

    info = detect()
    backend = args.backend or cfg["stt"]["backend"]
    stt_backend = {
        "cpu": "cpu",
        "cuda": "cuda",
    }.get(backend, "cpu")

    # auto → elegir segun energia (engine.choose_stt_backend es tdf del daemon)
    if backend == "auto":
        import engine
        stt_backend = engine.choose_stt_backend("auto", info)

    model = args.model or cfg["stt"]["model"]
    lang = args.lang or cfg["stt"].get("lang", "es")

    if args.cmd == "transcribe":
        text = transcribe(args.wav, model, stt_backend, lang)
        print(text)
    elif args.cmd == "fetch":
        fetch(args.model or model, stt_backend)
    elif args.cmd == "models":
        if os.path.isdir(MODEL_DIR):
            for name in sorted(os.listdir(MODEL_DIR)):
                print(name)
        else:
            print("(sin modelos descargados)")


if __name__ == "__main__":
    main()