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
import sys
import wave

import numpy as np


def main() -> None:
    # Este script se llama kokoro.py y vive en linux/voice → enmascara al
    # paquete pip `kokoro`. Muevo el dir del script al final de sys.path para
    # que `from kokoro import KPipeline` resuelva al paquete instalado.
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path = [p for p in sys.path if os.path.abspath(p or "") != here] \
        + [here]
    ap = argparse.ArgumentParser(prog="voice-kokoro")
    ap.add_argument("-t", "--text", required=True)
    ap.add_argument("-o", "--out", default=os.path.join("/tmp", "voice-kokoro.wav"))
    ap.add_argument("-l", "--lang", default="en")
    ap.add_argument("-v", "--voice", default=None,
                    help="voz kokoro (es: ef_dora|em_alex|em_santa; en: af_heart|af_bella|...)")
    a = ap.parse_args()

    from kokoro import KPipeline  # import tardío: solo si se usa kokoro

    # lang_code de KPipeline: 'a'=en-US, 'b'=en-UK, 'e'=es (multilingüe).
    # El español de kokoro es "thin" (3 voces, sin grade) → por defecto se
    # usa piper para es; kokoro brilla en inglés (af_heart, calidad A).
    code_map = {"en": "a", "es": "e", "es-MX": "e", "es-ES": "e"}
    voice_map = {"a": "af_heart", "b": "bf_emma", "e": "ef_dora"}
    code = code_map.get(a.lang, "a")
    voice = a.voice or voice_map[code]
    pipeline = KPipeline(lang_code=code, repo_id="hexgrad/Kokoro-82M")
    chunks = [audio for _, _, audio in pipeline(a.text, voice=voice, speed=1.0)]
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