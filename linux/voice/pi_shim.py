#!/usr/bin/env python3
# pi_shim.py — puente Ollama -> agente headless para el cerebro de Omar.
#
# Omar (y cualquier cliente que hable el protocolo de Ollama) le pega a
# /api/chat esperando {message:{role,content,tool_calls?}}. Este shim extrae la
# frase del usuario del contexto, la manda al cerebro headless (`voice-hermes`,
# o el que diga VOICE_BRAIN_BIN) y devuelve su respuesta como la del asistente.
#
# El agente actúa por su cuenta con sus herramientas (terminal -> hyprctl,
# wpctl, ...) y Omar solo relata la respuesta hablada. Así el fallback "no es
# un comando fijo" lo resuelve el harness elegido, localmente y sin opencode.
#
# Nombre del servicio y del archivo: histórico (`voice-pi-shim`), cuando el
# único cerebro era Pi.
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

# VOICE_BRAIN_BIN manda; VOICE_PI_BIN queda por compatibilidad con configs
# viejas. Por defecto, el cerebro actual: Hermes headless.
VOICE_BRAIN = (
    os.environ.get("VOICE_BRAIN_BIN")
    or os.environ.get("VOICE_PI_BIN")
    or os.path.join(os.path.expanduser("~"), ".local/bin", "voice-hermes")
)
TIMEOUT = float(os.environ.get("VOICE_BRAIN_SHIM_TIMEOUT", os.environ.get("VOICE_PI_SHIM_TIMEOUT", "90")))
PORT = int(os.environ.get("VOICE_PI_SHIM_PORT", "11435"))

# La última línea del contexto de Omar es "petición: <frase>".
REQUEST_RE = re.compile(r"^\s*petici[oó]n:\s*(.+?)\s*$", re.IGNORECASE | re.MULTILINE)


def extract_request(content: str) -> str:
    matches = REQUEST_RE.findall(content or "")
    if matches:
        return matches[-1].strip()
    # Sin el formato de Omar: usar el texto tal cual (servidor genérico).
    return (content or "").strip()


def ask_brain(text: str, dry: bool = False) -> str:
    if not text:
        return ""
    env = dict(os.environ)
    if dry:
        env["VOICE_BRAIN_DRY"] = "1"
    try:
        proc = subprocess.run(
            [VOICE_BRAIN, text],
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
            # "pi" queda listado para clientes/configs viejas; Omar no lo valida.
            self._json({"models": [{"name": "hermes", "model": "hermes"}, {"name": "pi", "model": "pi"}]})
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
            # warmup: no hay nada que calentar del lado del agente.
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
        reply = ask_brain(text, dry=bool(req.get("omar_dry")))
        self._json({"message": {"role": "assistant", "content": reply}, "done": True})


def main() -> int:
    if not os.path.exists(VOICE_BRAIN):
        print(f"pi_shim: no existe {VOICE_BRAIN}", file=sys.stderr)
        return 1
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"pi_shim: Ollama->{os.path.basename(VOICE_BRAIN)} escuchando en 127.0.0.1:{PORT}", file=sys.stderr)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
