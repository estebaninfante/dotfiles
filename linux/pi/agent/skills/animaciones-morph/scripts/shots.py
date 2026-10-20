#!/usr/bin/env python3
"""Corre un harness QML offscreen en Quickshell y guarda PNGs.

Uso:  shots.py HARNESS.qml OUT_DIR [nombre ...]
      SHOT_SCALE (default 1.25), THEME_FILE, OMARCHY_PATH

El harness tiene que importar Quickshell, mostrar la escena en una
FloatingWindow y guardar cada forma con grabToImage + saveToFile(nombre + ".png")
(relativo: el script corre con cwd en OUT_DIR), terminando con
console.log("SHOTS_OK") justo antes de Qt.quit(). La receta está en SKILL.md.
No abre ventanas: usa QT_QPA_PLATFORM=offscreen.
"""
import os
import subprocess
import sys
from pathlib import Path

if len(sys.argv) < 3:
    sys.exit(__doc__)
harness, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
names = sys.argv[3:]
out.mkdir(parents=True, exist_ok=True)
run = out / ".run"
run.mkdir(mode=0o700, exist_ok=True)

env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
           QT_SCALE_FACTOR=os.environ.get("SHOT_SCALE", "1.25"),
           XDG_RUNTIME_DIR=str(run))
# El harness guarda con saveToFile(nombre + ".png"), relativo: corre con cwd
# en OUT_DIR, así no hay rutas mágicas dentro del QML.
result = subprocess.run(["qs", "-p", str(harness), "--no-color"],
                        env=env, cwd=str(out), capture_output=True, text=True, timeout=120)
log = result.stdout + result.stderr
bad = [l for l in log.splitlines()
       if any(k in l for k in ("ReferenceError", "TypeError", "Error:", "is not a type",
                               "Binding loop", "Unable to assign"))]
print("\n".join(bad[:30]) or "sin warnings")
missing = [n for n in names if not (out / (n + ".png")).exists()]
if missing:
    print("no se guardaron:", ", ".join(missing))
if not (result.returncode == 0 and "SHOTS_OK" in log and not bad and not missing):
    print(log[-3000:])
    sys.exit(1)
