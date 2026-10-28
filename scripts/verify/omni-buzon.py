#!/usr/bin/env python3
"""
verify/omni-buzon.py — el buzón hablado de Omni (corte #1 del agente nuevo).

Comprueba, sin audio y sin red: que un agente pueda dejar un aviso, que Omni lo
diga con su nombre y el texto literal, que respete la urgencia, que junte los
pendientes en una sola frase, que marque lo escuchado, y que sin avisos no
invente nada.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
OMNI = HOME / ".local/bin/omni"
QUIET = "--quiet" in sys.argv
fallas = 0


def ok(msg: str) -> None:
    if not QUIET:
        print(f"  ok    {msg}")


def falla(msg: str) -> None:
    global fallas
    fallas += 1
    print(f"  FALLA {msg}")


class Omni:
    def __init__(self, estado: Path) -> None:
        self.estado = estado

    def run(self, *args: str) -> tuple[dict, float]:
        env = dict(os.environ)
        env.update(
            {
                "OMNI_ESTADO": str(self.estado),
                # Un servidor de modelos inexistente: si este corte llamara a
                # un modelo, fallaría o colgaría.
                "OMNI_LLAMA_URL": "http://127.0.0.1:9",
            }
        )
        t0 = time.time()
        r = subprocess.run(
            [str(OMNI), *args, "--json", "--dry-run"],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        dt = time.time() - t0
        if r.returncode != 0:
            raise RuntimeError(f"omni falló: {r.stderr.strip()}")
        return json.loads(r.stdout), dt

    def avisar(self, agente: str, texto: str, *extra: str) -> dict:
        return self.run("avisar", "--agente", agente, "--texto", texto, *extra)[0]


raiz = Path(tempfile.mkdtemp(prefix="omni-verify-"))
o = Omni(raiz / "estado")

# 1) un aviso urgente se dice con nombre, texto literal y prioridad
try:
    out = o.avisar("puma", "Terminé el ticket del panel. **Verificado** con la suite.", "--urgente")
    dicho = out["dicho"]
    assert dicho.startswith("Urgente, de Puma"), dicho
    assert "Terminé el ticket del panel" in dicho, dicho
    assert "**" not in dicho and "Verificado con la suite" in dicho, dicho
    assert dicho.count(".") >= 2 and ".." not in dicho, f"puntuación rara: {dicho}"
    ok("un aviso urgente se dice con nombre, texto literal y prioridad")
except AssertionError as exc:
    falla(f"aviso urgente: {exc}")
except Exception as exc:
    falla(f"aviso urgente (excepción): {exc}")

# 2) con --callar no habla y queda pendiente
try:
    out = o.avisar("tucan", "Necesito que decidas sobre el layout.", "--callar")
    assert out["dicho"] == "", out["dicho"]
    b, _ = o.run("buzon")
    assert b["pendientes"] == 1, b
    assert b["avisos"][0]["agente"] == "tucan", b["avisos"]
    assert b["avisos"][0]["texto"] == "Necesito que decidas sobre el layout.", b["avisos"][0]
    ok("con --callar no habla, y el aviso queda en el buzón con su agente")
except AssertionError as exc:
    falla(f"callar: {exc}")
except Exception as exc:
    falla(f"callar (excepción): {exc}")

# 3) tres pendientes se juntan en UNA frase (nada de ráfagas)
try:
    o.avisar("zorro", "Se rompió el build.", "--callar")
    o.avisar("vicuna", "Estoy esperando tu decisión.\n\n```bash\nnpm test\n```", "--callar")
    out, _ = o.run("dime")
    dicho = out["dicho"]
    assert dicho.startswith("Tres avisos"), dicho
    for quien in ("Tucan", "Zorro", "Vicuna"):
        assert quien in dicho, f"falta {quien}: {dicho}"
    assert "npm test" not in dicho, "el código no se dice"
    assert out["pendientes"] == 0, out
    ok("tres avisos pendientes se dicen en una sola frase, sin código")
except AssertionError as exc:
    falla(f"lote: {exc}")
except Exception as exc:
    falla(f"lote (excepción): {exc}")

# 4) lo escuchado no se repite
try:
    out, _ = o.run("dime")
    assert out["pendientes"] == 0, out
    assert "No hay avisos pendientes" in out["dicho"], out["dicho"]
    ok("lo ya escuchado no se repite: sin pendientes lo dice")
except AssertionError as exc:
    falla(f"repetir: {exc}")
except Exception as exc:
    falla(f"repetir (excepción): {exc}")

# 5) sin modelo: rápido y sin red
try:
    _, dt = o.run("buzon")
    assert dt < 3, f"tardó {dt:.1f}s"
    ok("no llama a ningún modelo (respuesta instantánea)")
except AssertionError as exc:
    falla(f"sin modelo: {exc}")
except Exception as exc:
    falla(f"sin modelo (excepción): {exc}")

# 6) el registro sobrevive: cada aviso quedó en disco con su texto
try:
    lineas = (raiz / "estado" / "buzon.jsonl").read_text(encoding="utf-8").strip().splitlines()
    assert len(lineas) == 4, f"esperaba 4 avisos, hay {len(lineas)}"
    ok("cada aviso queda registrado en disco")
except AssertionError as exc:
    falla(f"registro: {exc}")
except Exception as exc:
    falla(f"registro (excepción): {exc}")

if fallas:
    print(f"omni-buzon: {fallas} falla(s)")
    sys.exit(1)
print("omni-buzon: ok")
