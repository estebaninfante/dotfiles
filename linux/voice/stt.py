#!/usr/bin/env python3
# stt.py — Speech-to-Text local via Handy (whisper, GPU Vulkan / CPU).
#
# Handy ya es un paquete del sistema y trae whisper-medium instalado. Aquí
# solo envolvemos su CLI headless, MSIME:
#   handy --transcribe-file <wav> --json [--model <id>] [--device-index <N>]
# La salida es una única línea JSON:
#   {"audio_secs":...,"best_ms":...,"bound_backend":"Vulkan0","load_ms":...,
#    "model":"...whisper-medium-Q8_0.gguf","text":"...","transcribe_ms":[...]}
#
# Uso (interno, via el CLI voice):
#   stt.py transcribe <wav> [--model id] [--device index] [--lang es]
#   stt.py devices            # lista dispositivos handy (vulkan/cpu)
#   stt.py models [--json]    # modelos Handy instalados
#   stt.py accelerator        # dispositivo efectivo (via engine)
#
# Sin descargas de modelos (Handy los gestiona). STT = leer `text` del JSON.

import argparse
import json
import os
import subprocess
import sys

from engine import choose_handy_device, load_config

# Handy escribe warnings de fontconfig a stderr; lo suprimimos para que stdout
# (el JSON) quede limpio y parseable.
HANDY = "/run/current-system/sw/bin/handy"


def _run_handy(argv: list[str], timeout: int = 300) -> subprocess.CompletedProcess:
    return subprocess.run([HANDY] + argv, capture_output=True, text=True,
                          timeout=timeout)


def transcribe(wav: str, model: str | None, device_index: int | None, lang: str) -> str:
    if not os.path.isfile(wav):
        raise SystemExit(f"stt: no encuentro '{wav}'")
    argv = ["--transcribe-file", wav, "--json"]
    if model:
        argv += ["--model", model]
    if device_index is not None:
        argv += ["--device-index", str(device_index)]
    r = _run_handy(argv)
    if r.returncode != 0:
        raise SystemExit(f"stt: handy rc={r.returncode}: {r.stderr[-300:]}")
    try:
        data = json.loads((r.stdout or "").strip() or "null")
    except json.JSONDecodeError:
        raise SystemExit("stt: handy no devolvió JSON válido")
    if not data:
        return ""
    text = (data.get("text") or "").strip()
    return text


def list_devices() -> None:
    argv = ["--list-devices"]
    r = _run_handy(argv)
    print((r.stdout or "").strip())


def list_models(json_out: bool) -> None:
    argv = ["--list-models"]
    r = _run_handy(argv)
    lines = [ln for ln in (r.stdout or "").splitlines()]
    if json_out:
        print(json.dumps(lines))
    else:
        for ln in lines:
            print(ln)


def main() -> None:
    ap = argparse.ArgumentParser(prog="stt")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("transcribe")
    p.add_argument("wav")
    p.add_argument("--model", default=None,
                   help="id completo del catálogo Handy, ej. handy-computer/…/whisper-medium-Q8_0.gguf")
    p.add_argument("--device", type=int, default=None)
    p.add_argument("--lang", default=None)

    sub.add_parser("devices")
    p = sub.add_parser("models")
    p.add_argument("--json", action="store_true")

    sub.add_parser("accelerator")

    args = ap.parse_args()
    cfg = load_config()

    if args.cmd == "devices":
        list_devices()
        return
    if args.cmd == "models":
        list_models(args.json)
        return

    info = {}
    from engine import detect
    info = detect()
    dev = choose_handy_device(cfg["stt"]["accelerator"], info)

    if args.cmd == "accelerator":
        print(f"accelerator={dev['accelerator']} device_index={dev['index']}")
        return

    model = args.model or cfg["stt"]["model"]
    lang = args.lang or cfg["stt"].get("lang", "es")
    text = transcribe(args.wav, model, dev["index"], lang)
    print(text)


if __name__ == "__main__":
    main()