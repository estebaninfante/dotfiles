#!/usr/bin/env python3
"""micguard — ¿está el usuario dictando (micrófono tomado por un dictado)?

Una sola pregunta para que la voz no pise al dictado: mientras dictás, el TTS
no habla ni empieza a hablar. La respuesta sale de los mismos turnos que ya
usan los dictados, así que no hay que enterarse de cada herramienta nueva:

    $XDG_RUNTIME_DIR/omar/mic-busy      lo escribe `omar dictate` y handy-dictado
    $XDG_RUNTIME_DIR/omar/dictate.pid   el turno del gesto de dictado (toggle)

Las dos anotaciones llevan el PID del que graba. Si ese proceso ya no está, la
anotación es basura de una salida bruta y no cuenta; si tiene más de
MAX_AGE_MS, tampoco (un dictado no dura eso).

Red de seguridad: si Handy o Voxtype graban por su cuenta (sin pasar por
`handy-dictado`, que es quien anota `mic-busy`), se los ve igual por PipeWire:
un stream de captura cuyo proceso es `handy`/`voxtype` también es dictado. Se
consulta como mucho una vez por segundo para no pagar `pactl` en cada vuelta.

Uso:
    python3 micguard.py --busy   # 0 = micrófono libre, 1 = hay dictado
    python3 micguard.py --json   # {"busy": bool, "reason": str, "pid": N}
"""

import json
import os
import subprocess
import sys
import time

# Mismo tope que usan `mic-busy` y el turno del dictado en Omar.
MAX_AGE_MS = 5 * 60 * 1000

# Dictados que no siempre pasan por `handy-dictado`: si están capturando el
# micrófono, también hay que callarse.
_DICTATION_BINS = ("handy", "voxtype")
_CACHE_MS = 1000
_cache: dict = {"at": 0.0, "owner": (None, None)}


def _omar_dir() -> str:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    return os.path.join(runtime, "omar")


def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False


def _pid_anotado(path: str) -> int | None:
    """PID anotado en `path`, si la anotación está fresca y es válida."""
    try:
        edad = time.time() * 1000 - os.stat(path).st_mtime * 1000
        if edad > MAX_AGE_MS:
            return None
        pid = int(open(path, encoding="utf-8").read().strip())
        return pid if pid > 0 else None
    except (OSError, ValueError):
        return None


def _cmdline(pid: int) -> str:
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            return fh.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def _pipewire_dictation() -> tuple[str | None, int | None]:
    """Dictado que graba por su cuenta (Handy/Voxtype), visto en PipeWire."""
    try:
        salida = subprocess.run(
            ["pactl", "-f", "json", "list", "source-outputs"],
            capture_output=True, text=True, timeout=2,
        ).stdout
        streams = json.loads(salida or "[]")
    except Exception:
        return (None, None)
    for stream in streams:
        crudo = (stream.get("properties") or {}).get("application.process.id")
        try:
            pid = int(crudo)
        except (TypeError, ValueError):
            continue
        cmd = _cmdline(pid)
        bajo = cmd.lower()
        if any(binario in bajo for binario in _DICTATION_BINS):
            nombre = (cmd.split() or ["dictado"])[0].rsplit("/", 1)[-1]
            return (f"dictado en curso ({nombre}, pid {pid})", pid)
    return (None, None)


def owner() -> tuple[str | None, int | None]:
    """(motivo, pid) del dictado en curso, o (None, None) si el mic está libre."""
    folder = _omar_dir()
    for nombre in ("mic-busy", "dictate.pid"):
        pid = _pid_anotado(os.path.join(folder, nombre))
        if not pid or not _alive(pid):
            continue
        # PID reusado: la anotación dice dictado pero el proceso es otra cosa.
        cmd = _cmdline(pid)
        if cmd and "dictate" not in cmd and "handy" not in cmd:
            continue
        return (f"dictado en curso ({nombre}, pid {pid})", pid)
    ahora = time.time() * 1000
    if ahora - _cache["at"] >= _CACHE_MS:
        _cache["at"] = ahora
        _cache["owner"] = _pipewire_dictation()
    return _cache["owner"]


def busy() -> bool:
    return owner()[0] is not None


def main(argv: list[str]) -> int:
    motivo, pid = owner()
    if "--json" in argv:
        print(json.dumps({"busy": motivo is not None, "reason": motivo or "", "pid": pid}))
        return 0
    if motivo:
        if "--busy" in argv:
            print(motivo, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
