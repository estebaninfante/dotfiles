#!/usr/bin/env python3
"""chatterbox_server.py — Persistent Chatterbox TTS server.

Keeps the model loaded in memory across requests. Avoids 9s startup
penalty per synthesis call.

Protocol (JSON lines on stdin/stdout):
  Request:  {"text": "...", "output": "/path.wav", "lang": "es"}
  Response: {"ok": true, "stats": {...}} or {"ok": false, "error": "..."}
  Ping:     {"ping": true}
  Pong:     {"pong": true}

Shutdown:  {"shutdown": true}  or  EOF on stdin
"""

import json
import os
import sys
import time

# Add venv site-packages
VENV_PATH = os.environ.get(
    "CHATTERBOX_VENV", os.path.expanduser("~/.local/share/tts/venv")
)

def _setup_path():
    lib_dir = os.path.join(VENV_PATH, "lib")
    if os.path.isdir(lib_dir):
        for entry in os.listdir(lib_dir):
            site = os.path.join(lib_dir, entry, "site-packages")
            if os.path.isdir(site) and site not in sys.path:
                sys.path.insert(0, site)

_setup_path()

_model = None
_model_type = None


def _load_model(t3_model: str = "v3"):
    global _model, _model_type
    if _model is not None and _model_type == t3_model:
        return _model
    import torch
    from chatterbox.mtl_tts import ChatterboxMultilingualTTS

    print(f"[chatterbox-server] Loading model t3_model={t3_model}...", file=sys.stderr)
    t0 = time.time()
    _model = ChatterboxMultilingualTTS.from_pretrained(device="cuda", t3_model=t3_model)
    _model_type = t3_model
    vram = os.popen("nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits").read().strip()
    print(f"[chatterbox-server] Model ready in {time.time()-t0:.1f}s (VRAM: {vram} MiB)", file=sys.stderr)
    return _model


def synthesize(text: str, output_path: str, lang: str = "es",
               ref_path: str = None, t3_model: str = "v3") -> dict:
    import torch
    import soundfile as sf

    model = _load_model(t3_model)
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
    # Load model eagerly on startup
    _load_model("v3")
    print("[chatterbox-server] Ready", file=sys.stderr)

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

        text = req.get("text", "").strip()
        output = req.get("output", "")
        lang = req.get("lang", "es")
        ref = req.get("ref")
        model_ver = req.get("model", "v3")

        if not text or not output:
            _respond({"ok": False, "error": "missing text or output"})
            continue

        try:
            stats = synthesize(text, output, lang=lang, ref_path=ref, t3_model=model_ver)
            _respond({"ok": True, "stats": stats})
        except Exception as e:
            _respond({"ok": False, "error": str(e)})


def _respond(obj: dict):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
