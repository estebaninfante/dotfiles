from __future__ import annotations

import os
from pathlib import Path

from ai_chats.config import Paths
from ai_chats.db import FileRecord, connect, count_chunks, list_files
from ai_chats.embed import run_embed
from ai_chats.ingest import run_ingest
from tests.fake_embedder import FakeEmbedder

DOC = "\n".join(
    [
        "---",
        "title: Embed",
        "url: https://chatgpt.com/c/embed",
        "---",
        "",
        "Linea inicial del documento de prueba.",
        "",
        "Linea final con contenido suficiente para formar un chunk.",
        "",
    ]
)

QUERY = "documento de prueba"


def _paths(tmp_path: Path) -> Paths:
    return Paths(root=tmp_path / "store", staging=tmp_path / "staging")


def _seed(paths: Paths) -> str:
    paths.staging.mkdir(parents=True, exist_ok=True)
    (paths.staging / "doc.md").write_text(DOC, encoding="utf-8")
    run_ingest(paths, settle_secs=0)
    rows = _rows(paths)
    assert len(rows) == 1
    return rows[0].path


def _rows(paths: Paths) -> list[FileRecord]:
    conn = connect(paths.db_path)
    try:
        return list_files(conn)
    finally:
        conn.close()


def test_embeds_new_file(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    stored = _seed(paths)
    embedder = FakeEmbedder()
    stats = run_embed(paths, embedder=embedder)
    assert stats.embedded_files == 1
    assert stats.chunks >= 1
    assert embedder.passage_calls
    rows = _rows(paths)
    assert rows[0].embedded_sha256 is not None
    assert Path(stored).is_file()


def test_incremental_skips_unchanged(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    _seed(paths)
    first = FakeEmbedder()
    run_embed(paths, embedder=first)
    second = FakeEmbedder()
    stats = run_embed(paths, embedder=second)
    assert stats.embedded_files == 0
    assert stats.unchanged == 1
    assert second.passage_calls == []


def test_changed_file_reembedded(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    stored = _seed(paths)
    run_embed(paths, embedder=FakeEmbedder())
    target = Path(stored)
    target.write_text(DOC.replace("inicial", "modificado"), encoding="utf-8")
    stat = target.stat()
    os.utime(target, ns=(stat.st_atime_ns, stat.st_mtime_ns + 10_000_000_000))
    stats = run_embed(paths, embedder=FakeEmbedder())
    assert stats.embedded_files == 1
    assert _chunk_texts(paths)
    assert any("modificado" in text for text in _chunk_texts(paths))
    rows = _rows(paths)
    assert rows[0].embedded_sha256 is not None


def test_deleted_file_removes_chunks(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    stored = _seed(paths)
    run_embed(paths, embedder=FakeEmbedder())
    assert _chunk_total(paths) >= 1
    Path(stored).unlink()
    stats = run_embed(paths, embedder=FakeEmbedder())
    assert stats.removed_files == 1
    assert _chunk_total(paths) == 0
    assert _rows(paths) == []


def test_untracked_store_file_registered(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    directory = paths.platform_dir("ChatGPT")
    directory.mkdir(parents=True)
    (directory / "suelto.md").write_text(DOC, encoding="utf-8")
    stats = run_embed(paths, embedder=FakeEmbedder())
    assert stats.registered == 1
    assert stats.embedded_files == 1
    rows = _rows(paths)
    assert len(rows) == 1


def test_search_with_fake_embedder(tmp_path: Path) -> None:
    from ai_chats.search import search

    paths = _paths(tmp_path)
    stored = _seed(paths)
    embedder = FakeEmbedder()
    run_embed(paths, embedder=embedder)
    hits = search(paths, QUERY, 3, embedder=embedder)
    assert hits
    assert hits[0].source_path == stored
    assert embedder.query_calls == [QUERY]


def _chunk_total(paths: Paths) -> int:
    conn = connect(paths.db_path)
    try:
        return count_chunks(conn)
    finally:
        conn.close()


def _chunk_texts(paths: Paths) -> list[str]:
    conn = connect(paths.db_path)
    try:
        rows = conn.execute("SELECT chunk_text FROM chunks").fetchall()
        return [str(row["chunk_text"]) for row in rows]
    finally:
        conn.close()
