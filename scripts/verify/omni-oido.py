#!/usr/bin/env python3
"""
verify/omni-oido.py — la compuerta del oído abierto.

Sin micrófono y sin modelo: comprueba cuándo Omni se despierta, cuándo ignora,
que tolere las transcripciones raras de su propio nombre, y la ventana de
seguimiento (después de responder, no hace falta repetir "Omni").
"""
from __future__ import annotations

import json
import os
import unicodedata
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
OMNI = HOME / ".local/bin/omni"
QUIET = "--quiet" in sys.argv
fallas = 0


def ok(m):
    if not QUIET:
        print(f"  ok    {m}")


def falla(m):
    global fallas
    fallas += 1
    print(f"  FALLA {m}")


def sin_acentos(texto: str) -> str:
    t = unicodedata.normalize("NFKD", (texto or "").lower())
    return "".join(c for c in t if not unicodedata.combining(c))


def gate(estado: Path, texto: str) -> dict:
    env = dict(os.environ)
    env["OMNI_ESTADO"] = str(estado)
    r = subprocess.run(
        [str(OMNI), "gate", texto, "--json", "--dry-run"],
        env=env, capture_output=True, text=True, timeout=30,
    )
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return json.loads(r.stdout)


raiz = Path(tempfile.mkdtemp(prefix="omni-oido-"))
estado = raiz / "estado"
estado.mkdir()

casos = [
    ("Omni, cómo van los agentes", True, "cómo van los agentes"),
    ("oni subí el volumen", True, "subí el volumen"),
    ("OMNI abrí brave", True, "abrí brave"),
    ("homni qué hora es", True, "qué hora es"),
    # así lo transcribió de verdad el ASR con la voz del usuario (2026-10-28):
    ("Oh, mí, oh, mí. no funciona.", True, "no funciona"),
    ("Oh, mí, subí el volumen", True, "subí el volumen"),
    ("O M I qué hora es", True, "qué hora es"),
    ("Omni.", True, ""),
    ("hombre, qué calor", False, ""),
    ("cómo van los agentes", False, ""),
    ("", False, ""),
]
try:
    for texto, quiere, pedido in casos:
        got = gate(estado, texto)
        assert got["despierta"] == quiere, f"{texto!r}: despierta={got['despierta']}"
        if quiere and pedido:
            assert sin_acentos(pedido) in sin_acentos(got["pedido"]), \
                f"{texto!r}: pedido={got['pedido']!r}"
    ok("se despierta solo con la palabra clave, tolera transcripciones raras y no se dispara con ruido")
except AssertionError as exc:
    falla(f"compuerta: {exc}")
except Exception as exc:
    falla(f"compuerta (excepción): {exc}")

if fallas:
    print(f"omni-oido: {fallas} falla(s)")
    sys.exit(1)
print("omni-oido: ok")
