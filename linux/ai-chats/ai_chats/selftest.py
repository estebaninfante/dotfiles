from __future__ import annotations

import asyncio
import subprocess
import sys
import tempfile
import time
from collections.abc import Sequence
from pathlib import Path

from .config import Paths
from .db import FileRecord, connect, count_chunks, list_files
from .embed import run_embed
from .ingest import run_ingest
from .search import search

STARTUP_LIMIT_SECS = 2.0
PROBE_TIMEOUT_SECS = 20.0
MCP_TOOL = "search_conversations"
PIPELINE_QUERY = "migracion del pinguino antartica"
PIPELINE_MARKER = "pingüino de magallanes"

CHATGPT_DOC = "\n".join(
    [
        "---",
        "title: Ingest prueba",
        "url: https://chatgpt.com/c/prueba-1",
        "---",
        "",
        "# Prueba de ingesta",
        "",
        "Pregunta: como funciona el modo turbo?",
        "Respuesta: funciona con checkpoints.",
        "",
    ]
)

PIPELINE_DOC = "\n".join(
    [
        "---",
        "title: Pipeline prueba",
        "url: https://chatgpt.com/c/prueba-2",
        "---",
        "",
        "# Prueba de pipeline",
        "",
        f"{PIPELINE_MARKER} vive en la antartida y migra cada invierno.",
        "",
    ]
)


def run_ingest_selftest() -> int:
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="ai-chats-ingest-") as tmp:
        paths = _temp_paths(tmp)
        paths.staging.mkdir(parents=True)
        (paths.staging / "chat.md").write_text(CHATGPT_DOC, encoding="utf-8")
        (paths.staging / "chat-copy.md").write_text(CHATGPT_DOC, encoding="utf-8")

        first = run_ingest(paths, settle_secs=0)
        if first.moved != 1 or first.discarded != 1:
            failures.append(f"esperaba moved=1 discarded=1, obtuve {first.moved}/{first.discarded}")
        if list(paths.staging.glob("*.md")):
            failures.append("el staging quedo con archivos")
        stored_files = sorted(paths.platform_dir("ChatGPT").glob("*.md"))
        if len(stored_files) != 1:
            failures.append(f"esperaba 1 archivo en ChatGPT/, obtuve {len(stored_files)}")
            stored_files = [paths.platform_dir("ChatGPT") / "chat.md"]
        base_name = stored_files[0].name

        (paths.staging / base_name).write_text(
            CHATGPT_DOC.replace("turbo", "turbo dos"), encoding="utf-8"
        )
        second = run_ingest(paths, settle_secs=0)
        stem = base_name.removesuffix(".md")
        suffixed = paths.platform_dir("ChatGPT") / f"{stem}-2.md"
        if second.moved != 1 or not suffixed.is_file():
            failures.append("no aplico el sufijo -2 con nombre base repetido")

        third = run_ingest(paths, settle_secs=0)
        if third.moved != 0 or third.discarded != 0:
            failures.append(f"ingesta no idempotente: {third.moved}/{third.discarded}")

        conn = connect(paths.db_path)
        try:
            rows = list_files(conn)
        finally:
            conn.close()
        if len(rows) != 2:
            failures.append(f"esperaba 2 filas en files, obtuve {len(rows)}")
    return _report("ai-chats-ingest", failures)


def run_pipeline_selftest() -> int:
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="ai-chats-pipeline-") as tmp:
        paths = _temp_paths(tmp)
        paths.staging.mkdir(parents=True)
        (paths.staging / "migracion.md").write_text(PIPELINE_DOC, encoding="utf-8")

        ingested = run_ingest(paths, settle_secs=0)
        if ingested.moved != 1:
            failures.append(f"ingest movio {ingested.moved}, esperaba 1")
        rows = _rows(paths)
        if len(rows) != 1:
            failures.append(f"esperaba 1 archivo registrado, obtuve {len(rows)}")
        stored_path = rows[0].path if rows else ""

        embedded = run_embed(paths)
        if embedded.embedded_files != 1 or embedded.chunks < 1:
            failures.append(f"embed: files={embedded.embedded_files} chunks={embedded.chunks}")

        hits = search(paths, PIPELINE_QUERY, 3)
        if not hits:
            failures.append("search sin resultados")
        elif hits[0].source_path != stored_path:
            failures.append(f"top hit {hits[0].source_path} != {stored_path}")
        elif hits[0].score <= 0:
            failures.append(f"score no positivo: {hits[0].score}")

        repeat = run_embed(paths)
        if repeat.embedded_files != 0 or repeat.unchanged != 1:
            failures.append(f"embed no incremental: {repeat.embedded_files}/{repeat.unchanged}")

        if stored_path:
            failures.extend(_mutate_and_remove(paths, stored_path))
    return _report("ai-chats-pipeline", failures)


def run_mcp_selftest() -> int:
    failures: list[str] = []
    startup = _startup_seconds()
    if startup >= STARTUP_LIMIT_SECS:
        failures.append(f"arranque {startup:.2f}s >= {STARTUP_LIMIT_SECS}s")
    tools: list[str] = []
    try:
        tools = asyncio.run(asyncio.wait_for(_probe_tools(), PROBE_TIMEOUT_SECS))
    except TimeoutError:
        failures.append("sondeo MCP por stdio no respondio")
    except Exception as exc:
        failures.append(f"sondeo MCP fallo: {exc}")
    if tools and MCP_TOOL not in tools:
        failures.append(f"tool {MCP_TOOL} ausente: {tools}")
    return _report("ai-chats-mcp", failures)


def _temp_paths(tmp: str) -> Paths:
    base = Path(tmp)
    return Paths(root=base / "store", staging=base / "staging")


def _rows(paths: Paths) -> list[FileRecord]:
    conn = connect(paths.db_path)
    try:
        return list_files(conn)
    finally:
        conn.close()


def _mutate_and_remove(paths: Paths, stored_path: str) -> list[str]:
    failures: list[str] = []
    target = Path(stored_path)
    target.write_text(
        PIPELINE_DOC.replace("antartida", "patagonia").replace("invierno", "primavera"),
        encoding="utf-8",
    )
    changed = run_embed(paths)
    if changed.embedded_files != 1:
        failures.append(f"re-embed por cambio no corrio: {changed.embedded_files}")
    conn = connect(paths.db_path)
    try:
        total = count_chunks(conn)
    finally:
        conn.close()
    if total < 1:
        failures.append("chunks vacios tras cambio")

    target.unlink()
    removed = run_embed(paths)
    if removed.removed_files != 1:
        failures.append(f"borrado no detectado: {removed.removed_files}")
    conn = connect(paths.db_path)
    try:
        leftover = count_chunks(conn)
    finally:
        conn.close()
    if leftover != 0:
        failures.append(f"quedaron {leftover} chunks huerfanos")
    return failures


def _startup_seconds() -> float:
    start = time.perf_counter()
    proc = subprocess.run(
        [sys.executable, "-c", "from ai_chats.mcp_server import build_server; build_server()"],
        capture_output=True,
        timeout=PROBE_TIMEOUT_SECS,
    )
    elapsed = time.perf_counter() - start
    if proc.returncode != 0:
        return STARTUP_LIMIT_SECS
    return elapsed


async def _probe_tools() -> list[str]:
    from mcp import ClientSession, StdioServerParameters
    from mcp.client.stdio import stdio_client

    params = StdioServerParameters(command=sys.executable, args=["-m", "ai_chats.mcp_server"])
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            listed = await session.list_tools()
            return [tool.name for tool in listed.tools]


def _report(label: str, failures: Sequence[str]) -> int:
    if not failures:
        print(f"{label} selftest OK")
        return 0
    for failure in failures:
        print(f"{label} selftest FAIL: {failure}", file=sys.stderr)
    return 1
