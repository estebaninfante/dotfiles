from __future__ import annotations

import argparse
import os
import shutil
import sqlite3
import sys
import time
from collections.abc import Sequence
from dataclasses import dataclass, field
from pathlib import Path

from .classify import classify_platform
from .config import Paths, ensure_layout
from .db import FileRecord, connect, known_hashes, upsert_file
from .hashing import sha256_bytes
from .lock import FileLock

SETTLE_SECS = 2.0
ENV_SETTLE = "AI_CHATS_SETTLE_SECS"


@dataclass
class IngestStats:
    moved: int = 0
    discarded: int = 0
    fresh: int = 0
    errors: list[str] = field(default_factory=list)


def run_ingest(paths: Paths, settle_secs: float = SETTLE_SECS) -> IngestStats:
    ensure_layout(paths)
    stats = IngestStats()
    with FileLock(paths.lock_path):
        conn = connect(paths.db_path)
        try:
            digests = known_hashes(conn)
            for src in sorted(paths.staging.glob("*.md")):
                if not src.is_file():
                    continue
                _ingest_one(conn, paths, src, digests, settle_secs, stats)
            conn.commit()
        finally:
            conn.close()
    return stats


def _ingest_one(
    conn: sqlite3.Connection,
    paths: Paths,
    src: Path,
    digests: set[str],
    settle_secs: float,
    stats: IngestStats,
) -> None:
    try:
        stat = src.stat()
    except OSError as exc:
        stats.errors.append(f"{src.name}: {exc}")
        return
    if time.time() - stat.st_mtime < settle_secs:
        stats.fresh += 1
        return
    try:
        data = src.read_bytes()
    except OSError as exc:
        stats.errors.append(f"{src.name}: {exc}")
        return
    digest = sha256_bytes(data)
    if digest in digests:
        try:
            src.unlink()
        except OSError as exc:
            stats.errors.append(f"{src.name}: {exc}")
            return
        stats.discarded += 1
        return
    text = data.decode("utf-8", errors="replace")
    platform = classify_platform(src.name, text)
    dest = paths.destination(platform, src.name)
    try:
        _move(src, dest)
    except OSError as exc:
        stats.errors.append(f"{src.name}: {exc}")
        return
    os.utime(dest, ns=(stat.st_atime_ns, stat.st_mtime_ns))
    upsert_file(
        conn,
        FileRecord(
            path=str(dest),
            sha256=digest,
            mtime=stat.st_mtime,
            platform=platform,
            embedded_sha256=None,
        ),
    )
    digests.add(digest)
    stats.moved += 1


def _move(src: Path, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.replace(src, dest)
    except OSError:
        shutil.copy2(src, dest)
        src.unlink()


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ai-chats-ingest")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        from .selftest import run_ingest_selftest

        return run_ingest_selftest()
    settle_secs = float(os.environ.get(ENV_SETTLE, str(SETTLE_SECS)))
    stats = run_ingest(Paths.default(), settle_secs=settle_secs)
    print(
        f"ai-chats-ingest: moved={stats.moved} discarded={stats.discarded}"
        f" fresh={stats.fresh} errors={len(stats.errors)}"
    )
    for error in stats.errors:
        print(f"ai-chats-ingest: {error}", file=sys.stderr)
    return 0
