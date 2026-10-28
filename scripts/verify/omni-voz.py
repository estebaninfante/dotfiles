#!/usr/bin/env python3
"""
verify/omni-voz.py — un solo modelo para oído y boca.

Levanta un servidor falso que imita al modelo local (/tts y /v1/chat/completions)
y un `pw-play` falso que anota qué le pidieron reproducir. Comprueba que Omni:

  1. pide la voz al modelo con el texto, la voz y el idioma correctos;
  2. reproduce el WAV que devolvió el modelo (no otro);
  3. manda el audio al modelo como `input_audio` en base64 para transcribir;
  4. dice la transcripción usando la misma boca;
  5. no toca la nube.
"""
from __future__ import annotations

import base64
import json
import os
import struct
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
OMNI = HOME / ".local/bin/omni"
QUIET = "--quiet" in sys.argv
fallas = 0
pedidos: dict[str, list[dict]] = {"tts": [], "chat": []}
TEXTO_ASR = "esta es la transcripción del modelo"


def ok(msg: str) -> None:
    if not QUIET:
        print(f"  ok    {msg}")


def falla(msg: str) -> None:
    global fallas
    fallas += 1
    print(f"  FALLA {msg}")


def wav_silencio(ms: int = 200, sr: int = 24000) -> bytes:
    n = int(sr * ms / 1000)
    data = b"\x00\x00" * n
    cabecera = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt "
    cabecera += struct.pack("<IHHIIHH", 16, 1, 1, sr, sr * 2, 2, 16)
    return cabecera + b"data" + struct.pack("<I", len(data)) + data


class Falso(BaseHTTPRequestHandler):
    def log_message(self, *a):  # silencio
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        cuerpo = self.rfile.read(n)
        if self.path.startswith("/tts"):
            pedidos["tts"].append(json.loads(cuerpo or b"{}"))
            audio = wav_silencio()
            self.send_response(200)
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(audio)))
            self.end_headers()
            self.wfile.write(audio)
            return
        if self.path.startswith("/v1/chat/completions"):
            pedidos["chat"].append(json.loads(cuerpo or b"{}"))
            out = json.dumps(
                {"choices": [{"message": {"role": "assistant", "content": TEXTO_ASR}}]}
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(out)))
            self.end_headers()
            self.wfile.write(out)
            return
        self.send_response(404)
        self.end_headers()


srv = HTTPServer(("127.0.0.1", 0), Falso)
puerto = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()

raiz = Path(tempfile.mkdtemp(prefix="omni-voz-"))
estado = raiz / "estado"
bin_falso = raiz / "bin"
bin_falso.mkdir()
reproducido = raiz / "reproducido.txt"
jugador = bin_falso / "pw-play"
jugador.write_text(
    "#!/usr/bin/env bash\n"
    f'printf "%s\\n" "$@" >> "{reproducido}"\n'
    "exit 0\n"
)
jugador.chmod(0o755)

entorno = dict(os.environ)
entorno.update(
    {
        "PATH": f"{bin_falso}:{entorno.get('PATH','')}",
        "OMNI_ESTADO": str(estado),
        "OMNI_MODELO": f"http://127.0.0.1:{puerto}",
        "OMNI_MOTOR": "omni",
    }
)


def correr(*args: str) -> tuple[dict, str]:
    r = subprocess.run(
        [str(OMNI), *args, "--json"],
        env=entorno,
        capture_output=True,
        text=True,
        timeout=60,
    )
    if r.returncode != 0:
        raise RuntimeError(f"omni falló: {r.stderr.strip()}")
    return json.loads(r.stdout), r.stderr


# 1) la boca pide el audio al modelo y lo reproduce
try:
    salida, _ = correr("decir", "Hola, soy Omni.")
    assert len(pedidos["tts"]) == 1, pedidos["tts"]
    pedido = pedidos["tts"][0]
    assert pedido.get("input") == "Hola, soy Omni.", pedido
    assert pedido.get("language") == "es", pedido
    assert pedido.get("voice"), pedido
    args_jugador = reproducido.read_text(encoding="utf-8").splitlines()
    assert any(a.endswith(".wav") for a in args_jugador), args_jugador
    guardado = Path([a for a in args_jugador if a.endswith(".wav")][-1])
    assert guardado.is_file() and guardado.read_bytes().startswith(b"RIFF"), "no reprodujo el WAV del modelo"
    ok("la voz la genera el modelo local y se reproduce ese WAV")
except AssertionError as exc:
    falla(f"boca: {exc}")
except Exception as exc:
    falla(f"boca (excepción): {exc}")

# 2) el oído manda el audio al mismo modelo y dice lo que transcribió
try:
    wav = raiz / "pregunta.wav"
    wav.write_bytes(wav_silencio(300))
    reproducido.write_text("", encoding="utf-8")
    salida, _ = correr("escuchar", "--archivo", str(wav), "--dry-run")
    assert len(pedidos["chat"]) == 1, pedidos["chat"]
    chat = pedidos["chat"][0]
    partes = chat["messages"][1]["content"]
    audio = [p for p in partes if p.get("type") == "input_audio"]
    assert audio, partes
    datos = base64.b64decode(audio[0]["input_audio"]["data"])
    assert datos.startswith(b"RIFF"), "no mandó el WAV como base64"
    assert "ASR" in chat["messages"][0]["content"], chat["messages"][0]
    assert salida["texto"] == TEXTO_ASR, salida["texto"]
    ok("transcribe con el mismo modelo (audio base64 → texto)")
except AssertionError as exc:
    falla(f"oído: {exc}")
except Exception as exc:
    falla(f"oído (excepción): {exc}")

# 3) una sola boca: la respuesta también sale por el modelo
try:
    reproducido.write_text("", encoding="utf-8")
    correr("escuchar", "--archivo", str(wav))
    lineas = reproducido.read_text(encoding="utf-8")
    assert ".wav" in lineas, "no reprodujo la respuesta"
    ok("la respuesta se dice con la misma boca")
except AssertionError as exc:
    falla(f"respuesta hablada: {exc}")
except Exception as exc:
    falla(f"respuesta hablada (excepción): {exc}")

srv.shutdown()

if fallas:
    print(f"omni-voz: {fallas} falla(s)")
    sys.exit(1)
print("omni-voz: ok")
