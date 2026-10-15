#!/usr/bin/env python3
# pi_shim.py — puente Ollama -> Pi headless para el cerebro de OmniVoz.
#
# OmniVoz (y cualquier cliente que hable el protocolo de Ollama) le pega a
# /api/chat esperando {message:{role,content,tool_calls?}}. Este shim extrae la
# frase del usuario del contexto, la manda a `voice-pi` (Pi headless, sin
# razonamiento ni extensiones) y devuelve su respuesta como la del asistente.
#
# Pi actúa por su cuenta con sus herramientas (bash -> hyprctl, wpctl, ...) y
# OmniVoz solo relata la respuesta hablada. Así el fallback "no es un comando
# fijo" lo resuelve Pi, localmente y sin opencode.
#
# Puerto: VOICE_PI_SHIM_PORT (default 11435).

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from spoken import clean  # noqa: E402

VOICE_PI = os.environ.get(
    "VOICE_PI_BIN", os.path.join(os.path.expanduser("~"), ".local/bin", "voice-pi")
)
TIMEOUT = float(os.environ.get("VOICE_PI_SHIM_TIMEOUT", "90"))
PORT = int(os.environ.get("VOICE_PI_SHIM_PORT", "11435"))

# La última línea del contexto de OmniVoz es "petición: <frase>".
REQUEST_RE = re.compile(r"^\s*petici[oó]n:\s*(.+?)\s*$", re.IGNORECASE | re.MULTILINE)


def extract_request(content: str) -> str:
    matches = REQUEST_RE.findall(content or "")
    if matches:
        return matches[-1].strip()
    # Sin el formato de OmniVoz: usar el texto tal cual (servidor genérico).
    return (content or "").strip()


def ask_pi(text: str, dry: bool = False) -> str:
    if not text:
        return ""
    env = dict(os.environ)
    if dry:
        env["VOICE_PI_DRY"] = "1"
    try:
        proc = subprocess.run(
            [VOICE_PI, text],
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
            env=env,
        )
    except subprocess.TimeoutExpired:
        return "Me tardé demasiado en resolver eso."
    out = (proc.stdout or "").strip()
    if not out:
        return "No pude resolver eso."
    return clean(out) or "No pude resolver eso."


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args) -> None:  # silencio
        pass

    def _json(self, obj: dict, code: int = 200) -> None:
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path.startswith("/api/tags"):
            self._json({"models": [{"name": "pi", "model": "pi"}]})
        else:
            self._json({"ok": True})

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            req = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            self._json({"error": "invalid JSON"}, 400)
            return

        if self.path.startswith("/api/generate"):
            # warmup: no hay nada que calentar del lado de Pi.
            self._json({"response": "", "done": True})
            return

        if not self.path.startswith("/api/chat"):
            self._json({"error": "not found"}, 404)
            return

        user_content = ""
        for msg in reversed(req.get("messages", [])):
            if msg.get("role") == "user":
                user_content = str(msg.get("content", ""))
                break
        text = extract_request(user_content)
        reply = ask_pi(text, dry=bool(req.get("omnivoz_dry")))
        self._json({"message": {"role": "assistant", "content": reply}, "done": True})


def main() -> int:
    if not os.path.exists(VOICE_PI):
        print(f"pi_shim: no existe {VOICE_PI}", file=sys.stderr)
        return 1
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"pi_shim: Ollama->Pi escuchando en 127.0.0.1:{PORT}", file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
