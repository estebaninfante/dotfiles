from __future__ import annotations

from pathlib import Path

import pytest

from ai_chats.config import Paths
from ai_chats.db import ChunkRow, Hit, connect, insert_chunks, serialize_vector
from ai_chats.search import format_hit, format_hits, search
from tests.fake_embedder import FakeEmbedder


def _hit(text: str = "hola mundo") -> Hit:
    return Hit(
        chunk_id=7,
        score=0.8123,
        source_path="/home/eztvn/ai-chats/ChatGPT/ejemplo.md",
        chunk_index=2,
        platform="ChatGPT",
        text=text,
    )


def test_format_hit_includes_score_path_and_chunk() -> None:
    rendered = format_hit(_hit())
    assert "[0.8123]" in rendered
    assert "/home/eztvn/ai-chats/ChatGPT/ejemplo.md" in rendered
    assert "ChatGPT #2" in rendered
    assert "hola mundo" in rendered


def test_format_hit_indents_multiline_text() -> None:
    rendered = format_hit(_hit(text="uno\ndos"))
    assert "    uno\n    dos" in rendered


def test_format_hits_empty() -> None:
    assert format_hits([]) == "sin resultados"


def test_format_hits_joins_with_separator() -> None:
    rendered = format_hits([_hit(), _hit(text="otro")])
    assert "\n\n---\n\n" in rendered


def test_search_rejects_empty_query(tmp_path: Path) -> None:
    paths = Paths(root=tmp_path / "store", staging=tmp_path / "staging")
    with pytest.raises(ValueError):
        search(paths, "   ", 3, embedder=FakeEmbedder())


def test_search_rejects_nonpositive_limit(tmp_path: Path) -> None:
    paths = Paths(root=tmp_path / "store", staging=tmp_path / "staging")
    with pytest.raises(ValueError):
        search(paths, "algo", 0, embedder=FakeEmbedder())


def test_search_returns_hits_from_index(tmp_path: Path) -> None:
    paths = Paths(root=tmp_path / "store", staging=tmp_path / "staging")
    vector = [0.0] * 384
    vector[0] = 1.0
    conn = connect(paths.db_path)
    try:
        insert_chunks(
            conn,
            [ChunkRow("/x.md", 0, "Varios", "contenido", serialize_vector(vector))],
        )
        conn.commit()
    finally:
        conn.close()
    hits = search(paths, "contenido", 3, embedder=FakeEmbedder())
    assert len(hits) == 1
    assert hits[0].source_path == "/x.md"
    assert hits[0].score > 0.99
