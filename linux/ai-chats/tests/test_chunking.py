from __future__ import annotations

from ai_chats.chunking import MAX_CHUNK_CHARS, chunk_markdown


def _heading(index: int) -> str:
    return chr(35) * 2 + f" Seccion {index}"


def _paragraph(word: str, words: int) -> str:
    return " ".join(f"{word}{number:03d}" for number in range(words))


def test_frontmatter_removed() -> None:
    doc = "\n".join(
        ["---", "title: oculto", "url: https://chatgpt.com/c/1", "---", "", "Cuerpo visible", ""]
    )
    chunks = chunk_markdown(doc)
    assert len(chunks) == 1
    assert "title: oculto" not in chunks[0].text
    assert "Cuerpo visible" in chunks[0].text


def test_heading_attaches_to_body() -> None:
    doc = "\n".join([_heading(1), "", "cuerpo del parrafo"])
    chunks = chunk_markdown(doc)
    assert len(chunks) == 1
    assert _heading(1) in chunks[0].text
    assert "cuerpo del parrafo" in chunks[0].text


def test_heading_lines_never_split() -> None:
    lines: list[str] = []
    for index in range(8):
        lines.append(_heading(index))
        lines.append("")
        lines.append(_paragraph(f"alpha{index} ", 55))
        lines.append("")
    doc = "\n".join(lines)
    chunks = chunk_markdown(doc)
    assert len(chunks) > 1
    for index in range(8):
        heading = _heading(index)
        assert any(heading in chunk.text for chunk in chunks)
        for chunk in chunks:
            for size in range(1, len(heading)):
                assert not chunk.text.endswith(heading[:size])


def test_overlap_repeats_tail() -> None:
    first = _paragraph("primero ", 62)
    second = _paragraph("segundo ", 62)
    third = _paragraph("tercero ", 62)
    doc = "\n\n".join([first, second, third])
    chunks = chunk_markdown(doc)
    assert len(chunks) == 3
    assert chunks[1].text.startswith(first[-200:])
    assert chunks[2].text.startswith(second[-200:])


def test_chunks_respect_max_chars() -> None:
    lines: list[str] = []
    for index in range(10):
        lines.append(_heading(index))
        lines.append("")
        lines.append(_paragraph(f"beta{index} ", 50))
        lines.append("")
    chunks = chunk_markdown("\n".join(lines))
    assert chunks
    assert all(len(chunk.text) <= MAX_CHUNK_CHARS for chunk in chunks)
    assert [chunk.index for chunk in chunks] == list(range(len(chunks)))


def test_oversized_block_split() -> None:
    big = _paragraph("término ", 500)
    chunks = chunk_markdown(big)
    assert len(chunks) >= 2
    assert all(0 < len(chunk.text) <= MAX_CHUNK_CHARS for chunk in chunks)


def test_empty_inputs() -> None:
    assert chunk_markdown("") == []
    assert chunk_markdown("   \n\n   ") == []
