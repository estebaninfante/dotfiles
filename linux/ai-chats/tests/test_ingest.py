from __future__ import annotations

from pathlib import Path

from ai_chats.config import Paths
from ai_chats.db import connect, list_files
from ai_chats.hashing import sha256_bytes
from ai_chats.ingest import run_ingest

CHATGPT_DOC = "\n".join(
    [
        "---",
        "title: Ingest",
        "url: https://chatgpt.com/c/demo",
        "---",
        "",
        "Conversacion de prueba sobre arquitectura de software.",
        "",
    ]
)


def _paths(tmp_path: Path) -> Paths:
    return Paths(root=tmp_path / "store", staging=tmp_path / "staging")


def _stage(paths: Paths, name: str, content: str) -> Path:
    paths.staging.mkdir(parents=True, exist_ok=True)
    target = paths.staging / name
    target.write_text(content, encoding="utf-8")
    return target


def test_moves_and_classifies(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    _stage(paths, "chat.md", CHATGPT_DOC)
    stats = run_ingest(paths, settle_secs=0)
    assert stats.moved == 1
    assert stats.errors == []
    stored = paths.platform_dir("ChatGPT") / "chat.md"
    assert stored.is_file()
    assert not list(paths.staging.glob("*.md"))
    conn = connect(paths.db_path)
    try:
        rows = list_files(conn)
    finally:
        conn.close()
    assert len(rows) == 1
    assert rows[0].path == str(stored)
    assert rows[0].sha256 == sha256_bytes(CHATGPT_DOC.encode())
    assert rows[0].platform == "ChatGPT"
    assert rows[0].embedded_sha256 is None


def test_dedupe_by_content_hash(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    _stage(paths, "chat.md", CHATGPT_DOC)
    _stage(paths, "chat-copia.md", CHATGPT_DOC)
    stats = run_ingest(paths, settle_secs=0)
    assert stats.moved == 1
    assert stats.discarded == 1
    assert not list(paths.staging.glob("*.md"))
    assert len(list(paths.platform_dir("ChatGPT").glob("*.md"))) == 1


def test_same_name_different_content_gets_suffix(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    _stage(paths, "chat.md", CHATGPT_DOC)
    run_ingest(paths, settle_secs=0)
    _stage(paths, "chat.md", CHATGPT_DOC.replace("arquitectura", "contabilidad"))
    stats = run_ingest(paths, settle_secs=0)
    assert stats.moved == 1
    assert (paths.platform_dir("ChatGPT") / "chat-2.md").is_file()


def test_idempotent_rerun(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    _stage(paths, "chat.md", CHATGPT_DOC)
    run_ingest(paths, settle_secs=0)
    stats = run_ingest(paths, settle_secs=0)
    assert stats.moved == 0
    assert stats.discarded == 0
    assert stats.fresh == 0


def test_fresh_file_skipped(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    _stage(paths, "recien.md", CHATGPT_DOC)
    stats = run_ingest(paths, settle_secs=3600.0)
    assert stats.fresh == 1
    assert stats.moved == 0
    assert (paths.staging / "recien.md").is_file()


def test_duplicate_of_stored_file_discarded(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    _stage(paths, "chat.md", CHATGPT_DOC)
    run_ingest(paths, settle_secs=0)
    _stage(paths, "repetido.md", CHATGPT_DOC)
    stats = run_ingest(paths, settle_secs=0)
    assert stats.discarded == 1
    assert stats.moved == 0
    conn = connect(paths.db_path)
    try:
        rows = list_files(conn)
    finally:
        conn.close()
    assert len(rows) == 1
