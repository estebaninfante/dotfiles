from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence

from .config import Paths
from .db import Hit, connect, index_compatible, search_chunks
from .embed import IncompatibleIndexError
from .embedder import Embedder, default_embedder

DEFAULT_K = 5


def search(
    paths: Paths,
    query: str,
    limit: int,
    embedder: Embedder | None = None,
) -> list[Hit]:
    clean = query.strip()
    if not clean:
        raise ValueError("consulta vacia")
    if limit < 1:
        raise ValueError("limit debe ser >= 1")
    active = embedder if embedder is not None else default_embedder()
    conn = connect(paths.db_path)
    try:
        if not index_compatible(conn):
            raise IncompatibleIndexError(
                "indice incompatible con el modelo actual: corre ai-chats-embed --rebuild"
            )
        vector = active.embed_query(clean)
        return search_chunks(conn, vector.tolist(), limit)
    finally:
        conn.close()


def format_hit(hit: Hit) -> str:
    indented = hit.text.replace("\n", "\n    ")
    return f"[{hit.score:.4f}] {hit.platform} #{hit.chunk_index} {hit.source_path}\n    {indented}"


def format_hits(hits: Sequence[Hit]) -> str:
    if not hits:
        return "sin resultados"
    return "\n\n---\n\n".join(format_hit(hit) for hit in hits)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ai-chats-search")
    parser.add_argument("query", nargs="*", help="consulta semantica")
    parser.add_argument("-k", "--limit", type=int, default=DEFAULT_K)
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        from .selftest import run_pipeline_selftest

        return run_pipeline_selftest()
    if not args.query:
        parser.error("falta la consulta")
    try:
        hits = search(Paths.default(), " ".join(args.query), args.limit)
    except (ValueError, RuntimeError) as exc:
        print(f"ai-chats-search: {exc}", file=sys.stderr)
        return 1
    print(format_hits(hits))
    return 0
