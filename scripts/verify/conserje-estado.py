#!/usr/bin/env python3
"""
verify/conserje-estado.py — el corte vertical #1 del conserje: contar cómo van
los agentes, con procedencia y sin modelo.

Fixtures propios: no toca las trazas reales ni habla ni llama a ningún modelo.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

HOME = Path(os.path.expanduser("~"))
CONSERJE = HOME / ".local/bin/conserje"
QUIET = "--quiet" in sys.argv
fallas = 0


def ok(msg: str) -> None:
    if not QUIET:
        print(f"  ok    {msg}")


def falla(msg: str) -> None:
    global fallas
    fallas += 1
    print(f"  FALLA {msg}")


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def armar_fixture(raiz: Path) -> Path:
    """Tres agentes: uno fresco, uno de hace horas, uno viejo (sin confirmar)."""
    trazas = raiz / "trazas"
    trazas.mkdir(parents=True)
    ahora = datetime.now(timezone.utc)
    casos = [
        ("T-AAA111", "puma", 16, ahora - timedelta(minutes=4), "nota de prueba"),
        ("T-BBB222", "tucan", 2, ahora - timedelta(hours=3), "esperando decisión"),
        ("T-CCC333", "zorro", 5, ahora - timedelta(hours=30), "cerró el ticket"),
    ]
    filas = [
        "# Trazas de agentes",
        "",
        "| ticket | agente | estado | tickets | actualizada | archivo |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for ticket, agente, n, cuando, evento in casos:
        filas.append(
            f"| {ticket} sesión {agente} | {agente} | activa | {n} | {iso(cuando)} | "
            f"[{ticket}](./{ticket}.md) |"
        )
        (trazas / f"{ticket}.md").write_text(
            "\n".join(
                [
                    f"# Traza {ticket} · sesión {agente}",
                    "",
                    f"- **agente:** {agente}",
                    "- **estado:** activa",
                    f"- **actualizada:** {iso(cuando)}",
                    "",
                    "## Detalle",
                    "",
                    f"  {cuando.strftime('%H:%M:%S')} · {evento}",
                    "",
                ]
            ),
            encoding="utf-8",
        )
    (trazas / "index.md").write_text("\n".join(filas) + "\n", encoding="utf-8")
    return trazas


def correr(trazas: Path, estado: Path, *args: str) -> tuple[dict, float]:
    env = dict(os.environ)
    env.update(
        {
            "CONSERJE_TRAZAS": str(trazas),
            "CONSERJE_ESTADO": str(estado),
            # Un servidor de modelos que no existe: si el corte #1 intentara
            # llamar a un modelo, esto lo delata (o cuelga, o falla).
            "CONSERJE_LLAMA_URL": "http://127.0.0.1:9",
        }
    )
    t0 = time.time()
    r = subprocess.run(
        [str(CONSERJE), *args],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    dt = time.time() - t0
    if r.returncode != 0:
        raise RuntimeError(f"conserje falló ({r.returncode}): {r.stderr.strip()}")
    return json.loads(r.stdout), dt


raiz = Path(tempfile.mkdtemp(prefix="conserje-verify-"))
trazas = armar_fixture(raiz)
estado = raiz / "estado"

# 1) ruta + procedencia + frase
try:
    salida, dt = correr(trazas, estado, "ask", "--text", "¿cómo van mis agentes?", "--json", "--dry-run")
    assert salida["route"] == "estado", f"route={salida['route']}"
    claims = salida["claims"]
    assert len(claims) == 3, f"esperaba 3 claims, hay {len(claims)}"
    for c in claims:
        archivo = c["fuente"].split("#")[0]
        assert Path(archivo).is_file(), f"fuente inexistente: {archivo}"
        assert c["actualizada"], "claim sin fecha"
    viejos = [c for c in claims if not c["verificado"]]
    assert len(viejos) == 1, f"esperaba 1 claim sin confirmar, hay {len(viejos)}"
    assert "sin confirmar" in viejos[0]["texto"], viejos[0]["texto"]
    dicho = salida["said"].lower()
    assert "puma" in dicho and "zorro" in dicho, salida["said"]
    assert "16" in salida["said"], "no dice los tickets"
    ok("cuenta los agentes con fuente, fecha y «sin confirmar» en lo viejo")
except AssertionError as exc:
    falla(f"estado: {exc}")
except Exception as exc:
    falla(f"estado (excepción): {exc}")

# 2) ningún modelo: lo declara y no hay llamada (el puerto está cerrado)
try:
    assert salida["decision"]["modelo"] == "ninguno", salida["decision"]
    assert dt < 5, f"tardó {dt:.1f}s: parece que llamó a un modelo"
    ok("no usa modelo ni red (decisión declarada y respuesta instantánea)")
except AssertionError as exc:
    falla(f"sin modelo: {exc}")

# 3) queda registro del pedido
try:
    salida2, _ = correr(trazas, estado, "ask", "--text", "cómo van los agentes", "--json", "--no-say")
    lineas = (estado / "decisions.jsonl").read_text(encoding="utf-8").strip().splitlines()
    assert lineas, "no registró nada en decisions.jsonl"
    ultimo = json.loads(lineas[-1])
    assert ultimo["route"] == "estado", ultimo
    assert ultimo["claims"] == 3, ultimo
    ok("deja registro del pedido (decisions.jsonl)")
except AssertionError as exc:
    falla(f"registro: {exc}")
except Exception as exc:
    falla(f"registro (excepción): {exc}")

# 4) sin registro de trazas no inventa
try:
    vacio = raiz / "vacio"
    vacio.mkdir()
    salida3, _ = correr(vacio, raiz / "estado2", "ask", "--text", "cómo van", "--json", "--dry-run")
    assert salida3["claims"] == [], salida3
    assert "no encuentro" in salida3["said"].lower(), salida3["said"]
    ok("sin datos no inventa: lo dice")
except AssertionError as exc:
    falla(f"sin datos: {exc}")
except Exception as exc:
    falla(f"sin datos (excepción): {exc}")

# 5) pedido desconocido: no adivina
try:
    salida4, _ = correr(trazas, estado, "ask", "--text", "arreglá el bug del panel", "--json", "--dry-run")
    assert salida4["route"] == "no_entendido", salida4["route"]
    assert "todavía no sé" in salida4["said"].lower(), salida4["said"]
    ok("un pedido que todavía no maneja no se inventa")
except AssertionError as exc:
    falla(f"desconocido: {exc}")
except Exception as exc:
    falla(f"desconocido (excepción): {exc}")

if fallas:
    print(f"conserje-estado: {fallas} falla(s)")
    sys.exit(1)
print("conserje-estado: ok")
