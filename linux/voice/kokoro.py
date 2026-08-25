#!/usr/bin/env python3
# kokoro.py — wrapper CLI del motor TTS neural Kokoro (opcional).
#
# Uso: kokoro.py -t "texto" [-o salida.wav] [-l en|es]
# Emite un WAV 24 kHz mono. Las voces se descargan en el primer uso desde
# HuggingFace (hexgrad/Kokoro-82M) a ~/.cache/huggingface.
#
# Es la capa TTS "kokoro" del sistema (config.toml → tts.engine = "kokoro").
# El daemon lo invoca como voz-kokoro (ver packages.nix). No es la vía
# principal: piper da mejor calidad/tasa en español y arranca sin descargas.

import argparse
import os
import wave

import numpy as np


def main() -> None:
    ap = argparse.ArgumentParser(prog="voice-kokoro")
    ap.add_argument("-t", "--text", required=True)
    ap.add_argument("-o", "--out", default=os.path.join("/tmp", "voice-kokoro.wav"))
    ap.add_argument("-l", "--lang", default="en")
    a = ap.parse_args()

    from kokoro import KPipeline  # import tardío: solo si se usa kokoro

    # lang_code de KPipeline: 'a'=en-US, 'b'=en-UK, 'e'=es (multilingüe,
    # voces disponibles según el paquete; si 'e' falla se cae a 'a').
    voice_map = {"a": "af_heart", "b": "bf_emma", "e": "em_england"}
    for code in ({"en": "a", "es": "e", "es-MX": "e", "es-ES": "e"}.get(a.lang, "a"), "a"):
        try:
            pipeline = KPipeline(lang_code=code, repo_id="hexgrad/Kokoro-82M")
            voice = voice_map[code]
            chunks = [audio for _, _, audio in pipeline(a.text, voice=voice, speed=1.0)]
            break
        except Exception:
            if code == "a":
                raise
    full = np.concatenate(chunks)
    s16 = (full * 32767).astype(np.int16)
    with wave.open(a.out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(24000)
        w.writeframes(s16.tobytes())
    print(a.out)


if __name__ == "__main__":
    main()