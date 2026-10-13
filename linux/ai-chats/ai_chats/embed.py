from __future__ import annotations

import argparse
import sqlite3
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from .chunking import chunk_markdown
from .classify import classify_platform
from .config import PLATFORMS, Paths, ensure_layout
from .db import (
    ChunkRow,
    FileRecord,
    connect,
    delete_chunks,
    delete_file,
    file_record,
    index_compatible,
    insert_chunks,
    list_files,
    mark_changed,
    recreate_index,
    serialize_vector,
    set_embedded,
    touch_mtime,
    upsert_file,
)
from .embedder import Embedder, default_embedder
from .hashing import sha256_file
from .lock import FileLock

TEXT_ENCODING = "utf-8"


@dataclass
class EmbedStats:
    embedded_files: int = 0
    removed_files: int = 0
    removed_chunks: int = 0
    chunks: int = 0
    unchanged: int = 0
    registered: int = 0


class IncompatibleIndexError(RuntimeError):
    pass


def run_embed(
    paths: Paths,
    embedder: Embedder | None = None,
    rebuild: bool = False,
) -> EmbedStats:
    ensure_layout(paths)
    active = embedder if embedder is not None else default_embedder()
    stats = EmbedStats()
    with FileLock(paths.lock_path):
        conn = connect(paths.db_path)
        try:
            if rebuild:
                recreate_index(conn)
            if not index_compatible(conn):
                raise IncompatibleIndexError(
                    "indice incompatible con el modelo actual: corre ai-chats-embed --rebuild"
                )
            stats.registered = _register_untracked(conn, paths)
            for record in list_files(conn):
                _sync_record(conn, record, active, stats)
            conn.commit()
        finally:
            conn.close()
    return stats


def _register_untracked(conn: sqlite3.Connection, paths: Paths) -> int:
    registered = 0
    for directory in sorted(paths.root.iterdir()):
        if not directory.is_dir() or directory.name.startswith("."):
            continue
        platform = directory.name if directory.name in PLATFORMS else None
        for md in sorted(directory.rglob("*.md")):
            if any(part.startswith(".") for part in md.parts):
                continue
            if file_record(conn, str(md)) is not None:
                continue
            text = md.read_text(encoding=TEXT_ENCODING, errors="replace")
            resolved = platform if platform is not None else classify_platform(md.name, text)
            upsert_file(
                conn,
                FileRecord(
                    path=str(md),
                    sha256=sha256_file(md),
                    mtime=md.stat().st_mtime,
                    platform=resolved,
                    embedded_sha256=None,
                ),
            )
            registered += 1
    return registered


def _sync_record(
    conn: sqlite3.Connection,
    record: FileRecord,
    embedder: Embedder,
    stats: EmbedStats,
) -> None:
    path = Path(record.path)
    if not path.is_file():
        stats.removed_chunks += delete_file(conn, record.path)
        stats.removed_files += 1
        return
    stat = path.stat()
    sha256 = record.sha256
    mtime = record.mtime
    if stat.st_mtime != record.mtime:
        sha256 = sha256_file(path)
        mtime = stat.st_mtime
        if sha256 != record.sha256:
            mark_changed(conn, record.path, sha256, mtime)
        else:
            touch_mtime(conn, record.path, mtime)
    if record.embedded_sha256 is not None and record.embedded_sha256 == sha256:
        stats.unchanged += 1
        return
    stats.removed_chunks += delete_chunks(conn, record.path)
    text = path.read_text(encoding=TEXT_ENCODING, errors="replace")
    chunks = chunk_markdown(text)
    if chunks:
        vectors = embedder.embed_passages([chunk.text for chunk in chunks])
        if len(vectors) != len(chunks):
            raise RuntimeError(
                f"embedder devolvio {len(vectors)} vectores para {len(chunks)} chunks"
            )
        rows = [
            ChunkRow(
                source_path=record.path,
                chunk_index=chunk.index,
                platform=record.platform,
                text=chunk.text,
                vector=serialize_vector(vector.tolist()),
            )
            for chunk, vector in zip(chunks, vectors, strict=True)
        ]
        insert_chunks(conn, rows)
        stats.chunks += len(rows)
    set_embedded(conn, record.path, sha256)
    stats.embedded_files += 1


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ai-chats-embed")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--rebuild", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        from .selftest import run_pipeline_selftest

        return run_pipeline_selftest()
    try:
        stats = run_embed(Paths.default(), rebuild=args.rebuild)
    except IncompatibleIndexError as exc:
        print(f"ai-chats-embed: {exc}", file=sys.stderr)
        return 1
    print(
        f"ai-chats-embed: embedded={stats.embedded_files} chunks={stats.chunks}"
        f" unchanged={stats.unchanged} removed_files={stats.removed_files}"
        f" removed_chunks={stats.removed_chunks} registered={stats.registered}"
    )
    return 0
