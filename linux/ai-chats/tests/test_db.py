from __future__ import annotations

import sqlite3
from pathlib import Path

from ai_chats.config import EMBEDDING_DIM, MODEL_NAME
from ai_chats.db import (
    ChunkRow,
    FileRecord,
    connect,
    count_chunks,
    count_chunks_for,
    delete_file,
    file_record,
    index_compatible,
    insert_chunks,
    known_hashes,
    list_files,
    mark_changed,
    recreate_index,
    search_chunks,
    serialize_vector,
    set_embedded,
    upsert_file,
)


def _connect(tmp_path: Path) -> sqlite3.Connection:
    return connect(tmp_path / "chats.sqlite")


def _vector(hot_index: int) -> list[float]:
    vector = [0.0] * EMBEDDING_DIM
    vector[hot_index] = 1.0
    return vector


def _record(path: str, sha256: str = "aaa", embedded: str | None = None) -> FileRecord:
    return FileRecord(
        path=path, sha256=sha256, mtime=100.0, platform="ChatGPT", embedded_sha256=embedded
    )


def test_schema_uses_vec0(tmp_path: Path) -> None:
    conn = _connect(tmp_path)
    try:
        tables = {str(row["name"]) for row in conn.execute("SELECT name FROM sqlite_master")}
        assert {"files", "chunks", "meta"} <= tables
        sql_row = conn.execute("SELECT sql FROM sqlite_master WHERE name = 'chunks'").fetchone()
        assert sql_row is not None and "vec0" in str(sql_row["sql"])
        assert index_compatible(conn)
    finally:
        conn.close()


def test_upsert_and_known_hashes(tmp_path: Path) -> None:
    conn = _connect(tmp_path)
    try:
        upsert_file(conn, _record("/a.md", "hash-a"))
        upsert_file(conn, _record("/b.md", "hash-b"))
        conn.commit()
        assert known_hashes(conn) == {"hash-a", "hash-b"}
        rows = list_files(conn)
        assert [row.path for row in rows] == ["/a.md", "/b.md"]
        assert rows[0].platform == "ChatGPT"
    finally:
        conn.close()


def test_upsert_same_sha_keeps_embedding(tmp_path: Path) -> None:
    conn = _connect(tmp_path)
    try:
        upsert_file(conn, _record("/a.md", "hash-a"))
        set_embedded(conn, "/a.md", "hash-a")
        upsert_file(conn, _record("/a.md", "hash-a"))
        conn.commit()
        row = file_record(conn, "/a.md")
        assert row is not None
        assert row.embedded_sha256 == "hash-a"
    finally:
        conn.close()


def test_upsert_changed_sha_invalidates_embedding(tmp_path: Path) -> None:
    conn = _connect(tmp_path)
    try:
        upsert_file(conn, _record("/a.md", "hash-a"))
        set_embedded(conn, "/a.md", "hash-a")
        upsert_file(conn, _record("/a.md", "hash-nuevo"))
        conn.commit()
        row = file_record(conn, "/a.md")
        assert row is not None
        assert row.embedded_sha256 is None
    finally:
        conn.close()


def test_mark_changed_clears_embedding(tmp_path: Path) -> None:
    conn = _connect(tmp_path)
    try:
        upsert_file(conn, _record("/a.md", "hash-a"))
        set_embedded(conn, "/a.md", "hash-a")
        mark_changed(conn, "/a.md", "hash-b", 200.0)
        conn.commit()
        row = file_record(conn, "/a.md")
        assert row is not None
        assert row.sha256 == "hash-b"
        assert row.mtime == 200.0
        assert row.embedded_sha256 is None
    finally:
        conn.close()


def test_delete_file_removes_chunks(tmp_path: Path) -> None:
    conn = _connect(tmp_path)
    try:
        upsert_file(conn, _record("/a.md"))
        insert_chunks(
            conn,
            [
                ChunkRow("/a.md", 0, "ChatGPT", "hola", serialize_vector(_vector(0))),
                ChunkRow("/a.md", 1, "ChatGPT", "adios", serialize_vector(_vector(1))),
                ChunkRow("/b.md", 0, "Claude", "otro", serialize_vector(_vector(2))),
            ],
        )
        conn.commit()
        assert count_chunks_for(conn, "/a.md") == 2
        removed = delete_file(conn, "/a.md")
        conn.commit()
        assert removed == 2
        assert count_chunks_for(conn, "/a.md") == 0
        assert count_chunks_for(conn, "/b.md") == 1
        assert file_record(conn, "/a.md") is None
    finally:
        conn.close()


def test_search_orders_by_similarity(tmp_path: Path) -> None:
    conn = _connect(tmp_path)
    try:
        insert_chunks(
            conn,
            [
                ChunkRow("/a.md", 0, "ChatGPT", "primero", serialize_vector(_vector(0))),
                ChunkRow("/b.md", 0, "Claude", "segundo", serialize_vector(_vector(1))),
            ],
        )
        conn.commit()
        hits = search_chunks(conn, _vector(0), 5)
        assert len(hits) == 2
        assert hits[0].source_path == "/a.md"
        assert hits[0].score > hits[1].score
        assert hits[0].score > 0.99
        assert hits[0].text == "primero"
    finally:
        conn.close()


def test_search_empty_index(tmp_path: Path) -> None:
    conn = _connect(tmp_path)
    try:
        assert search_chunks(conn, _vector(0), 5) == []
        assert count_chunks(conn) == 0
    finally:
        conn.close()


def test_recreate_index_clears_embeddings(tmp_path: Path) -> None:
    conn = _connect(tmp_path)
    try:
        upsert_file(conn, _record("/a.md"))
        set_embedded(conn, "/a.md", "aaa")
        insert_chunks(conn, [ChunkRow("/a.md", 0, "ChatGPT", "x", serialize_vector(_vector(0)))])
        conn.commit()
        recreate_index(conn)
        assert count_chunks(conn) == 0
        row = file_record(conn, "/a.md")
        assert row is not None
        assert row.embedded_sha256 is None
        assert index_compatible(conn)
        meta = dict(conn.execute("SELECT key, value FROM meta").fetchall())
        assert meta["model"] == MODEL_NAME
    finally:
        conn.close()
