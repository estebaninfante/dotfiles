from __future__ import annotations

import re
from dataclasses import dataclass

MAX_CHUNK_CHARS = 1200
OVERLAP_CHARS = 200

FRONTMATTER_PATTERN = re.compile(r"\A---\s*\n.*?\n---\s*\n", re.DOTALL)
BLOCK_SPLIT_PATTERN = re.compile(r"\n\s*\n")
HEADING_PATTERN = re.compile(r"^#{1,6}\s")


@dataclass(frozen=True)
class Chunk:
    index: int
    text: str


def chunk_markdown(
    text: str,
    max_chars: int = MAX_CHUNK_CHARS,
    overlap: int = OVERLAP_CHARS,
) -> list[Chunk]:
    blocks = _blocks(_strip_frontmatter(text))
    chunks: list[str] = []
    prefix = ""
    index = 0
    total = len(blocks)
    while index < total:
        block = blocks[index]
        if len(block) > max_chars and not HEADING_PATTERN.match(block):
            chunks.extend(_split_oversized(block, max_chars, overlap))
            prefix = _overlap_prefix(chunks[-1], overlap)
            index += 1
            continue
        prefix = _fit_prefix(prefix, block, max_chars)
        limit = max_chars - _cost(prefix)
        current = block
        next_index = index + 1
        while next_index < total and len(current) + 2 + len(blocks[next_index]) <= limit:
            current = f"{current}\n\n{blocks[next_index]}"
            next_index += 1
        chunks.append(_join(prefix, current))
        prefix = _overlap_prefix(chunks[-1], overlap)
        index = next_index
    return [Chunk(index=position, text=value) for position, value in enumerate(chunks)]


def _strip_frontmatter(text: str) -> str:
    return FRONTMATTER_PATTERN.sub("", text, count=1)


def _blocks(text: str) -> list[str]:
    pieces = [piece.strip() for piece in BLOCK_SPLIT_PATTERN.split(text)]
    blocks: list[str] = []
    pending_heading: str | None = None
    for piece in pieces:
        if not piece:
            continue
        if _is_heading_only(piece):
            if pending_heading is not None:
                blocks.append(pending_heading)
            pending_heading = piece
            continue
        if pending_heading is not None:
            blocks.append(f"{pending_heading}\n\n{piece}")
            pending_heading = None
        else:
            blocks.append(piece)
    if pending_heading is not None:
        blocks.append(pending_heading)
    return blocks


def _is_heading_only(block: str) -> bool:
    return "\n" not in block and HEADING_PATTERN.match(block) is not None


def _cost(prefix: str) -> int:
    return len(prefix) + 2 if prefix else 0


def _fit_prefix(prefix: str, block: str, max_chars: int) -> str:
    if prefix and _cost(prefix) + len(block) > max_chars:
        return ""
    return prefix


def _join(prefix: str, body: str) -> str:
    return f"{prefix}\n\n{body}" if prefix else body


def _overlap_prefix(text: str, overlap: int) -> str:
    if len(text) <= overlap:
        return ""
    candidate = text[-overlap:]
    start = candidate.find("\n")
    if start != -1:
        candidate = candidate[start + 1 :]
    end = candidate.rfind("\n")
    if end != -1:
        candidate = candidate[:end]
    if not candidate:
        return ""
    return candidate


def _split_oversized(block: str, max_chars: int, overlap: int) -> list[str]:
    pieces: list[str] = []
    length = len(block)
    start = 0
    while start < length:
        end = min(start + max_chars, length)
        if end < length:
            cut = block.rfind(" ", start + max_chars // 2, end)
            if cut != -1:
                end = cut
        piece = block[start:end].strip()
        if piece:
            pieces.append(piece)
        if end >= length:
            break
        start = max(end - overlap, start + 1)
    return pieces
