#!/usr/bin/env python3
"""
verify/omni-web.py — la página local de Omni.

Sin micrófono, sin modelo y sin cerebro: comprueba que el servidor levanta en
un puerto libre, que sirve la página, que el estado sale del status.json real,
que el canal en vivo (SSE) manda algo, y que los pedidos mal formados se
rechazan en vez de romper el servidor.

Uso: scripts/verify/omni-web.sh [--quiet]
"""
from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
OMNI = HOME / "dotfiles/linux/bin/omni"
QUIET = "--quiet" in sys.argv
fallas = 0


def ok(m):
    if not QUIET:
        print(f"  ok    {m}")


def falla(m):
    global fallas
    fallas += 1
    print(f"  FALLA {m}")


def libre() -> int:
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    puerto = s.getsockname()[1]
    s.close()
    return puerto


def pedir(url, metodo="GET", cuerpo=None, timeout=10):
    datos = None
    cabeceras = {}
    if cuerpo is not None:
        datos = json.dumps(cuerpo).encode("utf-8")
        cabeceras["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=datos, headers=cabeceras, method=metodo)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")


# ── 1. sintaxis: el servidor vive en el mismo archivo que el resto de omni ──
try:
    r = subprocess.run([sys.executable, "-m", "py_compile", str(OMNI)], capture_output=True, text=True)
    assert r.returncode == 0, (r.stderr or "").strip()[:300]
    ok("omni compila")
except AssertionError as exc:
    falla(f"sintaxis: {exc}")
except Exception as exc:
    falla(f"sintaxis (excepción): {exc}")

# ── 2. servidor en un puerto libre, con estado de mentira ──
raiz = Path(tempfile.mkdtemp(prefix="omni-web-"))
puerto = libre()
base = f"http://127.0.0.1:{puerto}"
entorno = dict(os.environ, OMNI_ESTADO=str(raiz / "estado"))
(raiz / "estado").mkdir(parents=True, exist_ok=True)
# Un status.json mínimo: el servidor tiene que devolver lo que hay en disco.
(raiz / "estado" / "status.json").write_text(
    json.dumps({
        "state": "done",
        "level": 0.0,
        "updatedAt": 1,
        "activity": {"transcript": "hola", "result": "hola, ¿qué necesitás?"},
        "feed": [{"ts": 1, "state": "done", "transcript": "hola", "result": "hola, ¿qué necesitás?"}],
    }),
    encoding="utf-8",
)
servidor = subprocess.Popen(
    [sys.executable, str(OMNI), "web", "--puerto", str(puerto)],
    env=entorno, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
)
try:
    arriba = False
    for _ in range(100):
        try:
            urllib.request.urlopen(f"{base}/api/estado", timeout=1).read()
            arriba = True
            break
        except Exception:
            time.sleep(0.1)
    assert arriba, "el servidor no respondió en 10 s"
    ok("el servidor levanta y atiende en 127.0.0.1")
except AssertionError as exc:
    falla(str(exc))

if arriba:
    # ── 3. la página ──
    try:
        codigo, html = pedir(f"{base}/")
        assert codigo == 200, f"GET / devolvió {codigo}"
        for pieza in ('id="micro"', 'id="texto"', 'id="oido"', "/api/eventos", "/api/ptt"):
            assert pieza in html, f"la página no tiene {pieza}"
        assert "<script src" not in html and "cdn." not in html, "la página no puede pedir nada afuera"
        ok("la página trae el botón, el campo, el oído y no depende de la red")
    except AssertionError as exc:
        falla(f"página: {exc}")
    except Exception as exc:
        falla(f"página (excepción): {exc}")

    # ── 4. el estado refleja status.json ──
    try:
        codigo, texto = pedir(f"{base}/api/estado")
        estado = json.loads(texto)
        assert codigo == 200, f"GET /api/estado devolvió {codigo}"
        for clave, tipo in (("estado", dict), ("grabando", bool), ("modelo", bool),
                            ("oido", bool), ("pendientes", int)):
            assert clave in estado, f"falta {clave}"
            assert isinstance(estado[clave], tipo), f"{clave} no es {tipo.__name__}"
        assert estado["estado"]["activity"]["result"] == "hola, ¿qué necesitás?", "no leyó status.json"
        ok("el estado sale de status.json e incluye micrófono, modelo y oído")
    except AssertionError as exc:
        falla(f"estado: {exc}")
    except Exception as exc:
        falla(f"estado (excepción): {exc}")

    # ── 5. el canal en vivo manda el primer estado enseguida ──
    try:
        req = urllib.request.Request(f"{base}/api/eventos")
        evento = None
        with urllib.request.urlopen(req, timeout=6) as r:
            assert r.headers.get("Content-Type", "").startswith("text/event-stream"), \
                f"tipo inesperado: {r.headers.get('Content-Type')}"
            limite = time.time() + 6
            while time.time() < limite:
                linea = r.readline().decode("utf-8", "replace")
                if not linea:
                    break
                if linea.startswith("data: "):
                    evento = json.loads(linea[6:])
                    break
        assert evento is not None, "no llegó ningún evento en 6 s"
        assert "estado" in evento and "grabando" in evento, "el evento no trae el estado"
        ok("el canal en vivo manda el estado apenas se conecta")
    except AssertionError as exc:
        falla(f"eventos: {exc}")
    except Exception as exc:
        falla(f"eventos (excepción): {exc}")

    # ── 6. pedidos mal formados: se rechazan, no rompen ──
    casos = [
        ("/api/texto", {}, 400),
        ("/api/texto", {"texto": "   "}, 400),
        ("/api/oido", {}, 400),
        ("/api/loquesea", {}, 404),
    ]
    try:
        for ruta, cuerpo, esperado in casos:
            codigo, texto = pedir(f"{base}{ruta}", "POST", cuerpo)
            assert codigo == esperado, f"POST {ruta} {cuerpo} → {codigo} (esperaba {esperado})"
            assert "error" in json.loads(texto), f"POST {ruta} no explicó el error"
        ok("los pedidos incompletos se rechazan con su motivo")
    except AssertionError as exc:
        falla(f"validación: {exc}")
    except Exception as exc:
        falla(f"validación (excepción): {exc}")

    # ── 7. una dirección que no existe ──
    try:
        codigo, _ = pedir(f"{base}/no-existe")
        assert codigo == 404, f"GET /no-existe devolvió {codigo}"
        ok("lo que no existe devuelve 404")
    except AssertionError as exc:
        falla(f"404: {exc}")
    except Exception as exc:
        falla(f"404 (excepción): {exc}")

    # ── 8. el servidor sigue vivo después de todo eso ──
    try:
        codigo, _ = pedir(f"{base}/api/estado")
        assert codigo == 200, f"después de los pedidos raros devolvió {codigo}"
        ok("el servidor sigue en pie después de los pedidos raros")
    except AssertionError as exc:
        falla(f"salud final: {exc}")
    except Exception as exc:
        falla(f"salud final (excepción): {exc}")

servidor.terminate()
try:
    servidor.wait(timeout=5)
except Exception:
    servidor.kill()
shutil.rmtree(raiz, ignore_errors=True)

if fallas:
    print(f"omni-web: {fallas} falla(s)")
    sys.exit(1)
print("omni-web: ok")
