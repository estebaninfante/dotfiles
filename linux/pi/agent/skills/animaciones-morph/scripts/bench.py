#!/usr/bin/env python3
"""Mide el costo real de un frame de morph (JS + rasterizado).

Uso:  bench.py HARNESS.qml [presupuesto_ms] [frames]
      BENCH_DPR (default 1.25)

El harness dibuja N frames con un Canvas de `renderStrategy: Canvas.Immediate`
(dibuja en el hilo de GUI dentro de onPaint, así que el tiempo medido incluye
el rasterizado), cronometra alrededor del paint + un getImageData(0,0,1,1)
que fuerza el trabajo pendiente, y al final imprime:

    RASTER mean=7.82ms p50=8 p95=11 max=16

Sale con 1 si la media pasa el presupuesto (default 12 ms: deja lugar a los
otros 4-6 ms que cuesta el resto del shell en un frame de 16.7 ms).
"""
import os
import subprocess
import sys
from pathlib import Path

if len(sys.argv) < 2:
    sys.exit(__doc__)
harness = Path(sys.argv[1]).resolve()
budget = float(sys.argv[2]) if len(sys.argv) > 2 else 12.0
frames = int(sys.argv[3]) if len(sys.argv) > 3 else 140
dpr = os.environ.get("BENCH_DPR", "1.25")

run = harness.parent / ".run"
run.mkdir(mode=0o700, exist_ok=True)
env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=str(run),
           BENCH_DPR=dpr)
log = subprocess.run(["qs", "-p", str(harness), "--no-color"], env=env,
                     capture_output=True, text=True, timeout=240)
out = log.stdout + log.stderr
line = next((l for l in out.splitlines() if "RASTER" in l), None)
if not line:
    print(out[-3000:])
    sys.exit(1)
text = line.split("qml: ")[-1].strip()
print(text)
mean = float(text.split("mean=")[1].split("ms")[0])
if mean > budget:
    print(f"FALLA: {mean:.2f} ms por frame > presupuesto {budget:.1f} ms "
          f"({frames} frames, dpr {dpr})")
    sys.exit(1)
print(f"ok: {mean:.2f} ms por frame <= {budget:.1f} ms (dpr {dpr})")
