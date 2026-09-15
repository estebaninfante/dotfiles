#!/usr/bin/env python3
"""chatterbox_synth.py — Chatterbox Multilingual V3 TTS wrapper.

Called by the voice daemon to synthesize text to WAV.
Keeps the model loaded in memory across calls (module-level singleton).

Usage:
  python3 chatterbox_synth.py <text> <output.wav> [--lang es|en|...] [--ref <ref.wav>]

Environment:
  CHATTERBOX_VENV — path to the venv with chatterbox-tts (default: ~/.local/share/tts/venv)
"""

import argparse
import os
import sys
import time

VENV_PATH = os.environ.get(
    "CHATTERBOX_VENV", os.path.expanduser("~/.local/share/tts/venv")
)


def _setup_path():
    """Add venv site-packages to sys.path."""
    # Find the python3.XX in the venv
    venv_python = os.path.join(VENV_PATH, "bin")
    if os.path.isdir(venv_python):
        # Add venv lib to path so chatterbox imports work
        lib_dir = os.path.join(VENV_PATH, "lib")
        if os.path.isdir(lib_dir):
            for entry in os.listdir(lib_dir):
                site = os.path.join(lib_dir, entry, "site-packages")
                if os.path.isdir(site) and site not in sys.path:
                    sys.path.insert(0, site)


_setup_path()

# Global model singleton — loaded once, reused across calls
_model = None
_model_type = None  # "v3" or "v2"


def _load_model(device: str = "cuda", t3_model: str = "v3"):
    global _model, _model_type
    if _model is not None and _model_type == t3_model:
        return _model
    import torch
    from chatterbox.mtl_tts import ChatterboxMultilingualTTS

    print(f"[chatterbox] Loading model t3_model={t3_model} on {device}...", file=sys.stderr)
    t0 = time.time()
    _model = ChatterboxMultilingualTTS.from_pretrained(device=device, t3_model=t3_model)
    _model_type = t3_model
    print(f"[chatterbox] Model loaded in {time.time()-t0:.1f}s "
          f"(VRAM: {torch.cuda.memory_allocated(0)/1024**3:.2f} GB)", file=sys.stderr)
    return _model


def synthesize(text: str, output_path: str, lang: str = "es",
               ref_path: str = None, t3_model: str = "v3") -> dict:
    """Synthesize text to WAV file. Returns stats dict."""
    import torch
    import soundfile as sf

    model = _load_model(t3_model=t3_model)
    sr = model.sr

    gen_kwargs = {"language_id": lang}
    if ref_path and os.path.isfile(ref_path):
        gen_kwargs["audio_prompt_path"] = ref_path

    t0 = time.time()
    wav = model.generate(text, **gen_kwargs)
    t1 = time.time()

    audio_np = wav.squeeze().cpu().numpy()
    sf.write(output_path, audio_np, sr)

    duration = len(audio_np) / sr
    return {
        "duration": round(duration, 2),
        "synth_time": round(t1 - t0, 2),
        "rtf": round((t1 - t0) / duration, 2) if duration > 0 else 0,
        "sample_rate": sr,
        "lang": lang,
        "model": t3_model,
    }


def main():
    parser = argparse.ArgumentParser(description="Chatterbox Multilingual V3 TTS")
    parser.add_argument("text", help="Text to synthesize")
    parser.add_argument("output", help="Output WAV path")
    parser.add_argument("--lang", default="es", help="Language code (default: es)")
    parser.add_argument("--ref", default=None, help="Reference audio for voice cloning")
    parser.add_argument("--model", default="v3", choices=["v2", "v3"],
                        help="Model version (default: v3)")
    args = parser.parse_args()

    stats = synthesize(args.text, args.output, lang=args.lang,
                       ref_path=args.ref, t3_model=args.model)
    # Print stats as JSON for the daemon to parse
    import json
    print(json.dumps(stats))


if __name__ == "__main__":
    main()
