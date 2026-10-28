#!/usr/bin/env python3
"""
verify/lh-leer.py — arnés del puente LearnHarness → voz (sin audio).

Crea un directorio de chats falso, corre `lh-leer --once` en seco y compara lo
que habría dicho. No toca LearnHarness, ni el daemon, ni el micrófono.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
LH = HOME / ".local/bin/lh-leer"
QUIET = "--quiet" in sys.argv
fallas = 0


def ok(msg: str) -> None:
    if not QUIET:
        print(f"  ok    {msg}")


def falla(msg: str) -> None:
    global fallas
    fallas += 1
    print(f"  FALLA {msg}")


def mensaje(role: str, partes: list, ts: int = 1) -> dict:
    return {"id": f"msg_{role}_{ts}", "role": role, "content": partes, "timestamp": ts}


def escribir_chat(path: Path, mensajes: list) -> None:
    path.write_text(
        json.dumps({"id": "chat_test", "title": "prueba", "messages": mensajes, "turns": []}),
        encoding="utf-8",
    )


class Entorno:
    def __init__(self) -> None:
        self.dir = Path(tempfile.mkdtemp(prefix="lh-leer-verify-"))
        self.chats = self.dir / "chats"
        self.chats.mkdir()
        self.estado = self.dir / "estado.json"
        self.dry = self.dir / "dicho.log"
        self.toggle = self.dir / "leer.json"
        self.toggle.write_text('{"activado": true}', encoding="utf-8")
        self.chat = self.chats / "chat_test.json"

    def correr(self) -> str:
        env = dict(os.environ)
        env.update(
            LH_CHATS_DIR=str(self.chats),
            LH_LEER_STATE=str(self.estado),
            LH_LEER_DRY="1",
            LH_LEER_DRY_FILE=str(self.dry),
            PI_LEER_CONFIG=str(self.toggle),
        )
        env.pop("PI_LEER", None)
        antes = self.dry.read_text(encoding="utf-8") if self.dry.exists() else ""
        r = subprocess.run(
            [str(LH), "--once"], env=env, capture_output=True, text=True, timeout=60
        )
        if r.returncode != 0:
            raise RuntimeError(f"lh-leer --once falló: {r.stderr.strip()}")
        despues = self.dry.read_text(encoding="utf-8") if self.dry.exists() else ""
        return despues[len(antes) :]

    def apagar(self) -> None:
        self.toggle.write_text('{"activado": false}', encoding="utf-8")


# 1) Al arrancar NO lee el historial: toma línea base y calla.
e = Entorno()
escribir_chat(
    e.chat,
    [
        mensaje("user", "AI Engineer", 1),
        mensaje("assistant", [{"type": "text", "text": "Hola, arrancamos por embeddings."}], 2),
    ],
)
try:
    dicho = e.correr()
    assert dicho.strip() == "", f"leyó historial al arrancar: {dicho!r}"
    ok("al arrancar no lee el historial viejo")
except AssertionError as exc:
    falla(f"línea base: {exc}")

# 2) Un mensaje nuevo del tutor se dice, limpio y sin código.
escribir_chat(
    e.chat,
    [
        mensaje("user", "AI Engineer", 1),
        mensaje("assistant", [{"type": "text", "text": "Hola, arrancamos por embeddings."}], 2),
        mensaje(
            "assistant",
            [
                {"type": "thinking", "thinking": "pensando cosas que no se dicen"},
                {
                    "type": "text",
                    "text": "Un embedding es un vector.\n\n```py\nvec = [0.1]\n```\n¿Seguimos?",
                },
            ],
            3,
        ),
    ],
)
try:
    dicho = e.correr()
    assert "Un embedding es un vector" in dicho, f"no dijo la respuesta: {dicho!r}"
    assert "0.1" not in dicho, "el código no se dice"
    assert "pensando cosas" not in dicho, "el razonamiento no se dice"
    assert "¿Seguimos?" in dicho, "la pregunta sí se dice"
    ok("lee el mensaje nuevo, sin código ni razonamiento")
except AssertionError as exc:
    falla(f"mensaje nuevo: {exc}")

# 3) Correr de nuevo sin cambios no repite nada.
try:
    dicho = e.correr()
    assert dicho.strip() == "", f"repitió lo ya leído: {dicho!r}"
    ok("no repite lo que ya leyó")
except AssertionError as exc:
    falla(f"dedupe: {exc}")

# 4) Un turno que solo trae razonamiento (o herramientas) no se dice.
escribir_chat(
    e.chat,
    [
        mensaje("user", "AI Engineer", 1),
        mensaje("assistant", [{"type": "text", "text": "Hola, arrancamos por embeddings."}], 2),
        mensaje("assistant", [{"type": "thinking", "thinking": "solo pienso"}], 4),
    ],
)
try:
    dicho = e.correr()
    assert dicho.strip() == "", f"habló de un turno sin texto: {dicho!r}"
    ok("un turno sin texto no se dice")
except AssertionError as exc:
    falla(f"turno sin texto: {exc}")

# 5) Con la lectura apagada no dice nada, pero tampoco se atrasa.
escribir_chat(
    e.chat,
    [
        mensaje("user", "AI Engineer", 1),
        mensaje("assistant", [{"type": "text", "text": "Mensaje que no se escucha."}], 5),
    ],
)
e.apagar()
try:
    dicho = e.correr()
    assert dicho.strip() == "", f"habló con la lectura apagada: {dicho!r}"
    ok("con la lectura apagada no dice nada")
except AssertionError as exc:
    falla(f"apagada: {exc}")

if fallas:
    print(f"lh-leer: {fallas} falla(s)")
    sys.exit(1)
print("lh-leer: ok")
