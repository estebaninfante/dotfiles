from __future__ import annotations

from collections.abc import Sequence

import numpy as np
from numpy.typing import NDArray

from ai_chats.config import EMBEDDING_DIM


class FakeEmbedder:
    def __init__(self) -> None:
        self.passage_calls: list[list[str]] = []
        self.query_calls: list[str] = []

    def embed_passages(self, texts: Sequence[str]) -> list[NDArray[np.float32]]:
        self.passage_calls.append(list(texts))
        return [_vector(text) for text in texts]

    def embed_query(self, text: str) -> NDArray[np.float32]:
        self.query_calls.append(text)
        return _vector(text)


def _vector(text: str) -> NDArray[np.float32]:
    seed = float(sum(ord(char) for char in text) % 97) + 1.0
    vector = np.full(EMBEDDING_DIM, 0.01, dtype=np.float32)
    vector[0] = seed
    vector[1] = 1.0
    return vector
