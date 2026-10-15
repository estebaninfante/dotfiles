#!/usr/bin/env python3
"""mic-monitor — nivel y ganancia del micrófono en vivo.

Pensado para el widget de barra `eztvn.mic`: lee la fuente de audio *default*
de PipeWire, calcula el nivel RMS y emite **una línea JSON** cada ~64 ms para
que el QML la dibuje.

    {"level": 37, "peak": 82, "gain": 100, "mute": false, "device": "ALC257 Analog"}

Sigue los cambios de dispositivo: si cambia la fuente default, reconecta.
No escribe archivos temporales ni necesita daemon aparte.
"""
import json
import os
import select
import struct
import subprocess
import sys
import time

RATE = 16000
FRAME = 512          # muestras por bloque (~32 ms)
EMIT_EVERY = 2       # emitir cada 2 bloques (~64 ms)
INFO_EVERY = 1.0     # re-chequear fuente/ganancia cada 1 s


def default_source():
    try:
        return subprocess.check_output(
            ["pactl", "get-default-source"], text=True, stderr=subprocess.DEVNULL
        ).strip() or "@DEFAULT_SOURCE@"
    except Exception:
        return "@DEFAULT_SOURCE@"


def source_info(name):
    """Devuelve id/descripción/ganancia/mute de la fuente, o {} si falla."""
    try:
        out = subprocess.check_output(
            ["pactl", "-f", "json", "list", "sources"], text=True, stderr=subprocess.DEVNULL
        )
        arr = json.loads(out)
    except Exception:
        return {}
    for s in arr:
        if s.get("name") == name or name == "@DEFAULT_SOURCE@":
            pct = s.get("volume", {}).get("front-left", {}).get("value_percent", "0%")
            try:
                gain = int(str(pct).rstrip("%"))
            except ValueError:
                gain = 0
            return {
                "id": s.get("index"),
                "desc": s.get("description") or s.get("name") or "",
                "gain": gain,
                "mute": bool(s.get("mute")),
            }
    return {}


def open_parec(name):
    return subprocess.Popen(
        [
            "parec", "--device=" + name, "--format=float32le",
            "--rate=%d" % RATE, "--channels=1", "--raw", "--latency-msec=20",
        ],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, bufsize=0,
    )


def main():
    name = default_source()
    info = source_info(name)
    proc = open_parec(name)
    buf = b""
    frames = 0
    last_info = 0.0
    while True:
        try:
            r, _, _ = select.select([proc.stdout], [], [], 0.25)
        except (OSError, ValueError):
            r = []
        if proc.poll() is not None:
            proc = open_parec(name)
            buf = b""
            continue
        if r:
            try:
                data = os.read(proc.stdout.fileno(), FRAME * 4 * 8)
            except OSError:
                data = b""
            buf += data
        n = len(buf) // 4
        if n < FRAME:
            continue
        samples = struct.unpack("<%df" % FRAME, buf[: FRAME * 4])
        buf = buf[FRAME * 4:]
        peak = max((abs(x) for x in samples), default=0.0)
        rms = (sum(x * x for x in samples) / FRAME) ** 0.5
        level = int(min(100.0, rms * 350.0))
        peak_pct = int(min(100.0, peak * 180.0))

        frames += 1
        now = time.monotonic()
        if now - last_info >= INFO_EVERY:
            newname = default_source()
            if newname != name:
                name = newname
                try:
                    proc.terminate()
                    proc.wait(timeout=1)
                except Exception:
                    proc.kill()
                proc = open_parec(name)
                buf = b""
                frames = 0
            info = source_info(name)
            last_info = now

        if frames % EMIT_EVERY == 0:
            print(json.dumps({
                "level": level,
                "peak": peak_pct,
                "gain": info.get("gain", 0),
                "mute": info.get("mute", False),
                "device": info.get("desc", ""),
                "id": info.get("id"),
            }, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
