from __future__ import annotations

import sqlite3
import time
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import cast

import sqlite_vec

from .config import EMBEDDING_DIM, MODEL_NAME

SCHEMA_FILES = """
CREATE TABLE IF NOT EXISTS files (
    path TEXT PRIMARY KEY,
    sha256 TEXT NOT NULL,
    mtime REAL NOT NULL,
    platform TEXT NOT NULL,
    embedded_sha256 TEXT,
    ingested_at REAL NOT NULL
)
"""

SCHEMA_CHUNKS = f"""
CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING vec0(
    chunk_id INTEGER PRIMARY KEY,
    embedding float[{EMBEDDING_DIM}] distance_metric=cosine,
    source_path text,
    chunk_index integer,
    platform text,
    chunk_text text
)
"""

SCHEMA_META = """
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
)
"""

META_MODEL = "model"
META_DIM = "dim"
CONNECT_TIMEOUT = 30.0


@dataclass(frozen=True)
class FileRecord:
    path: str
    sha256: str
    mtime: float
    platform: str
    embedded_sha256: str | None


@dataclass(frozen=True)
class ChunkRow:
    source_path: str
    chunk_index: int
    platform: str
    text: str
    vector: bytes


@dataclass(frozen=True)
class Hit:
    chunk_id: int
    score: float
    source_path: str
    chunk_index: int
    platform: str
    text: str


def connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path, timeout=CONNECT_TIMEOUT)
    conn.row_factory = sqlite3.Row
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    conn.execute("PRAGMA journal_mode=WAL")
    ensure_schema(conn)
    return conn


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(SCHEMA_FILES)
    conn.executescript(SCHEMA_META)
    conn.executescript(SCHEMA_CHUNKS)
    conn.execute("INSERT OR IGNORE INTO meta(key, value) VALUES (?, ?)", (META_MODEL, MODEL_NAME))
    conn.execute(
        "INSERT OR IGNORE INTO meta(key, value) VALUES (?, ?)",
        (META_DIM, str(EMBEDDING_DIM)),
    )
    conn.commit()


def index_compatible(conn: sqlite3.Connection) -> bool:
    values = dict(conn.execute("SELECT key, value FROM meta").fetchall())
    return values.get(META_MODEL) == MODEL_NAME and values.get(META_DIM) == str(EMBEDDING_DIM)


def recreate_index(conn: sqlite3.Connection) -> None:
    conn.execute("DROP TABLE IF EXISTS chunks")
    conn.execute("UPDATE files SET embedded_sha256 = NULL")
    conn.commit()
    ensure_schema(conn)


def list_files(conn: sqlite3.Connection) -> list[FileRecord]:
    rows = conn.execute(
        "SELECT path, sha256, mtime, platform, embedded_sha256 FROM files ORDER BY path"
    ).fetchall()
    return [_file_record(row) for row in rows]


def file_record(conn: sqlite3.Connection, path: str) -> FileRecord | None:
    row = conn.execute(
        "SELECT path, sha256, mtime, platform, embedded_sha256 FROM files WHERE path = ?",
        (path,),
    ).fetchone()
    return None if row is None else _file_record(row)


def known_hashes(conn: sqlite3.Connection) -> set[str]:
    rows = conn.execute("SELECT sha256 FROM files").fetchall()
    return {str(row["sha256"]) for row in rows}


def upsert_file(conn: sqlite3.Connection, record: FileRecord) -> None:
    conn.execute(
        """
        INSERT INTO files(path, sha256, mtime, platform, embedded_sha256, ingested_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            sha256 = excluded.sha256,
            mtime = excluded.mtime,
            platform = excluded.platform,
            embedded_sha256 = CASE
                WHEN files.sha256 = excluded.sha256 THEN files.embedded_sha256
                ELSE NULL
            END
        """,
        (
            record.path,
            record.sha256,
            record.mtime,
            record.platform,
            record.embedded_sha256,
            time.time(),
        ),
    )


def touch_mtime(conn: sqlite3.Connection, path: str, mtime: float) -> None:
    conn.execute("UPDATE files SET mtime = ? WHERE path = ?", (mtime, path))


def mark_changed(conn: sqlite3.Connection, path: str, sha256: str, mtime: float) -> None:
    conn.execute(
        "UPDATE files SET sha256 = ?, mtime = ?, embedded_sha256 = NULL WHERE path = ?",
        (sha256, mtime, path),
    )


def set_embedded(conn: sqlite3.Connection, path: str, sha256: str) -> None:
    conn.execute("UPDATE files SET embedded_sha256 = ? WHERE path = ?", (sha256, path))


def delete_file(conn: sqlite3.Connection, path: str) -> int:
    removed = delete_chunks(conn, path)
    conn.execute("DELETE FROM files WHERE path = ?", (path,))
    return removed


def delete_chunks(conn: sqlite3.Connection, path: str) -> int:
    cursor = conn.execute("DELETE FROM chunks WHERE source_path = ?", (path,))
    return cursor.rowcount


def insert_chunks(conn: sqlite3.Connection, rows: Sequence[ChunkRow]) -> None:
    conn.executemany(
        "INSERT INTO chunks(embedding, source_path, chunk_index, platform, chunk_text)"
        " VALUES (?, ?, ?, ?, ?)",
        [(row.vector, row.source_path, row.chunk_index, row.platform, row.text) for row in rows],
    )


def count_chunks(conn: sqlite3.Connection) -> int:
    row = conn.execute("SELECT count(*) AS total FROM chunks").fetchone()
    return int(row["total"])


def count_chunks_for(conn: sqlite3.Connection, path: str) -> int:
    row = conn.execute(
        "SELECT count(*) AS total FROM chunks WHERE source_path = ?",
        (path,),
    ).fetchone()
    return int(row["total"])


def search_chunks(conn: sqlite3.Connection, vector: Sequence[float], limit: int) -> list[Hit]:
    total = count_chunks(conn)
    if total == 0:
        return []
    k = max(1, min(limit, total))
    rows = conn.execute(
        """
        SELECT chunk_id, distance, source_path, chunk_index, platform, chunk_text
        FROM chunks WHERE embedding MATCH ? AND k = ?
        """,
        (sqlite_vec.serialize_float32(list(vector)), k),
    ).fetchall()
    return [
        Hit(
            chunk_id=int(row["chunk_id"]),
            score=1.0 - float(row["distance"]),
            source_path=str(row["source_path"]),
            chunk_index=int(row["chunk_index"]),
            platform=str(row["platform"]),
            text=str(row["chunk_text"]),
        )
        for row in rows
    ]


def serialize_vector(vector: Sequence[float]) -> bytes:
    return cast(bytes, sqlite_vec.serialize_float32(list(vector)))


def _file_record(row: sqlite3.Row) -> FileRecord:
    embedded = row["embedded_sha256"]
    return FileRecord(
        path=str(row["path"]),
        sha256=str(row["sha256"]),
        mtime=float(row["mtime"]),
        platform=str(row["platform"]),
        embedded_sha256=None if embedded is None else str(embedded),
    )
