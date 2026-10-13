from __future__ import annotations

import argparse
from collections.abc import Sequence

from mcp.server.mcpserver import MCPServer

from .config import Paths
from .search import format_hits, search

MAX_K = 20
MIN_K = 1


def build_server() -> MCPServer:
    server = MCPServer("ai-chats")

    @server.tool()
    def search_conversations(query: str, k: int = 5) -> str:
        """Busqueda semantica sobre conversaciones ingeridas (embeddings locales + sqlite-vec)."""
        limit = max(MIN_K, min(k, MAX_K))
        try:
            hits = search(Paths.default(), query, limit)
        except Exception as exc:
            return f"error: {exc}"
        return format_hits(hits)

    return server


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="ai-chats-mcp")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        from .selftest import run_mcp_selftest

        return run_mcp_selftest()
    build_server().run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
