#!/usr/bin/env python3
# benchmark.py — mide TTS (kokoro/piper/espeak × es/en) en el hardware real.
#
# Mide por celda: tiempo a final de audio (s), pico RSS (MB), tiempo CPU
# (s, /proc/<pid>/stat) y pico VRAM (MB, nvidia-smi si hay GPU).
#
# La latencia "time to first audio" de kokoro/piper/espeak (no streaming)
# ≈ t_total (sintetizan el wav completo y luego se reproduce). Se incluye
# igual como aproximacion; el flujo real lo marca el daemon al encolar.
#
# Uso:  voice benchmark            (todas las celdas)
#       voice benchmark piper es    (motor+idioma concretos, opcional)
#
# Procura frases cortas y naturales, en-tono conversacional.

import json
import os
import subprocess
import sys
import time

from engine import find_piper_model

# (etiqueta, frase es, frase en) — frases típicas de voz conversacional.
PHRASES = [
    ("frase", "Hola, ¿puedes revisar este error de TypeScript?",
             "Hi, could you take a look at this TypeScript error?"),
    ("diag", "He terminado. Modifiqué cuatro archivos, y queda un error pendiente.",
             "Done. I modified four files, and one error is still pending."),
]

ENGINES = {
    "kokoro": {"es": "ef_dora", "en": "af_heart"},
    "piper":  {"es": "es_MX-claude-high", "en": "en_US-amy-medium"},
    "espeak": {"es": "es", "en": "en"},
}

HANDY = "/run/current-system/sw/bin/handy"  # no usado: benchmark es solo TTS


def synth_to_wav(engine: str, voice: str, lang: str, text: str, wav: str) -> bool:
    if engine == "espeak":
        return subprocess.run(
            ["espeak-ng", "-v", lang, "-s", "160", "-p", "50", "-w", wav, text],
            capture_output=True, timeout=300).returncode == 0
    if engine == "piper":
        model = find_piper_model(voice)
        if not model:
            return False
        return subprocess.run(
            ["piper", "--model", model, "--output_file", wav],
            input=text, capture_output=True, text=True, timeout=300).returncode == 0
    if engine == "kokoro":
        kokoro = "/run/current-system/sw/bin/voice-kokoro"
        if not os.path.exists(kokoro):
            return False
        langc = "en" if lang == "en" else "es"
        return subprocess.run(
            [kokoro, "-o", wav, "-l", langc, "-t", text, "-v", voice],
            capture_output=True, timeout=600).returncode == 0
    return False


def _peak_stats(pid: int) -> tuple[float, float]:
    """Pico RSS (MB) y CPU (s) de un proceso via /proc (muestreo)."""
    peak_rss = 0.0
    cpu_s = 0.0
    start = time.time()
    while time.time() - start < 120:
        try:
            with open(f"/proc/{pid}/status") as fh:
                for line in fh:
                    if line.startswith("VmRSS:"):
                        peak_rss = max(peak_rss, int(line.split()[1]) / 1024.0)
        except FileNotFoundError:
            break
        try:
            with open(f"/proc/{pid}/stat") as fh:
                parts = fh.read().split()
            # utime(14)+stime(15) en ticks
            ticks = int(parts[13]) + int(parts[14])
            cpu_s = ticks / os.sysconf("SC_CLK_TCK")
        except (FileNotFoundError, IndexError, OSError):
            pass
        time.sleep(0.04)
    return peak_rss, cpu_s


def nvidia_vram() -> float | None:
    try:
        r = subprocess.run(["nvidia-smi", "--query-gpu=memory.used",
                            "--format=csv,noheader,nounits"],
                           capture_output=True, text=True, timeout=5)
        return float(r.stdout.strip().splitlines()[0])
    except Exception:
        return None


def measure(engine: str, voice: str, lang: str, text: str) -> dict:
    wav = f"/tmp/voice-bench-{engine}-{lang}.wav"
    if os.path.exists(wav):
        os.remove(wav)
    t0 = time.monotonic()

    peak_vram = nvidia_vram()
    if engine == "espeak":
        argv = ["espeak-ng", "-v", lang, "-s", "160", "-p", "50", "-w", wav, text]
        stdin = None
    elif engine == "kokoro":
        argv = ["voice-kokoro", "-o", wav, "-l", ("en" if lang == "en" else "es"),
                "-t", text, "-v", voice]
        stdin = None
    else:  # piper
        model = find_piper_model(voice)
        if not model:
            raise RuntimeError(f"voz piper '{voice}' no instalada")
        argv = ["piper", "--model", model, "--output_file", wav]
        stdin = text
    proc = subprocess.Popen(argv, stdin=subprocess.PIPE if stdin is not None else None,
                            text=True)
    if stdin is not None:
        proc.stdin.write(stdin)
        proc.stdin.close()

    # muestreo de VRAM durante la sintesis
    while proc.poll() is None:
        v = nvidia_vram()
        if v is not None and (peak_vram is None or v > peak_vram):
            peak_vram = v
        time.sleep(0.05)
    proc.wait(timeout=300)
    t_total = time.monotonic() - t0
    peak_rss, cpu_s = _peak_stats(proc.pid)
    if os.path.exists(wav):
        os.remove(wav)
    return {
        "engine": engine, "lang": lang, "voice": voice,
        "t_total_s": round(t_total, 2), "peak_rss_mb": round(peak_rss, 1),
        "cpu_s": round(cpu_s, 2),
        "peak_vram_mb": round(peak_vram) if peak_vram is not None else None,
    }


def main() -> None:
    only_e = sys.argv[1] if len(sys.argv) > 1 else None
    only_l = sys.argv[2] if len(sys.argv) > 2 else None
    engines = [only_e] if only_e else list(ENGINES)
    langs = [only_l] if only_l else ["es", "en"]

    print(f"{'motor':8} {'lang':4} {'voz':18} {'t_total_s':>9} {'RSS(MB)':>8} "
          f"{'CPU(s)':>7} {'VRAM(MB)':>9}")
    print("-" * 66)
    for phrase_label, frase_es, frase_en in PHRASES:
        for lang in langs:
            for eng in engines:
                text = frase_es if lang == "es" else frase_en
                voice = ENGINES[eng][lang]
                try:
                    row = measure(eng, voice, lang, text)
                except Exception as e:
                    print(f"      {eng:8} {lang:4} {voice:18}  ERROR: {e}")
                    continue
                print(f"{row['engine']:8} {row['lang']:4} {row['voice']:18} "
                      f"{row['t_total_s']:>9} {row['peak_rss_mb']:>8} "
                      f"{row['cpu_s']:>7} {str(row['peak_vram_mb']):>9}")
    print("-" * 66)
    print("t_total_s = sintesis completa a wav (latencia time-to-first-audio ≈ total)")
    print("VRAM = pico durante sintesis (None si no hay nvidia-smi)")


if __name__ == "__main__":
    main()