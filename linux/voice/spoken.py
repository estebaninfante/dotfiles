#!/usr/bin/env python3
# spoken.py — deja una respuesta apta para oído: fuera bloques de código, HTML,
# markdown, etiquetas de razonamiento y saltos de línea. Se usa tanto en el CLI
# (`voice think`) como en el puente de OmniVoz (pi_shim.py).

from __future__ import annotations

import re
import sys


def clean(text: str) -> str:
    t = text or ""
    t = re.sub(r"```.*?```", " ", t, flags=re.S)          # bloques de código
    t = re.sub(r"~~~.*?~~~", " ", t, flags=re.S)
    t = re.sub(r"(?is) thinking.*?<｜end▁of▁thinking｜>", " ", t)         # razonamiento
    t = re.sub(r"</?think>", " ", t, flags=re.I)
    t = re.sub(r"<[^>]+>", " ", t)                         # HTML
    t = re.sub(r"`([^`]*)`", r"\1", t)                     # código inline
    t = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", t)        # imágenes
    t = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", t)         # links
    t = re.sub(r"^\s{0,3}#{1,6}\s*", "", t, flags=re.M)    # títulos
    t = re.sub(r"^\s*[-*+]\s+", "", t, flags=re.M)         # viñetas
    t = re.sub(r"[*_>#]+", "", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t


def main() -> int:
    data = sys.stdin.read() if len(sys.argv) < 2 else " ".join(sys.argv[1:])
    sys.stdout.write(clean(data))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
