from __future__ import annotations

import os
from collections.abc import Sequence
from typing import TYPE_CHECKING, Protocol

import numpy as np
from numpy.typing import NDArray

from .config import EMBEDDING_DIM, ENV_MODEL_CACHE, MODEL_NAME, model_cache_dir

if TYPE_CHECKING:
    from fastembed import TextEmbedding

QUERY_PREFIX = "query: "
PASSAGE_PREFIX = "passage: "
MODEL_FILE = "onnx/model.onnx"
MODEL_LICENSE = "mit"
MODEL_SIZE_GB = 0.12
ALREADY_REGISTERED = "already registered"


class Embedder(Protocol):
    def embed_passages(self, texts: Sequence[str]) -> list[NDArray[np.float32]]: ...

    def embed_query(self, text: str) -> NDArray[np.float32]: ...


_registered: bool = False
_model: TextEmbedding | None = None
_default: E5Embedder | None = None


class E5Embedder:
    def embed_passages(self, texts: Sequence[str]) -> list[NDArray[np.float32]]:
        if not texts:
            return []
        model = _get_model()
        return [
            np.asarray(vector, dtype=np.float32)
            for vector in model.embed([PASSAGE_PREFIX + text for text in texts])
        ]

    def embed_query(self, text: str) -> NDArray[np.float32]:
        model = _get_model()
        vector = next(iter(model.embed([QUERY_PREFIX + text])))
        return np.asarray(vector, dtype=np.float32)


def default_embedder() -> E5Embedder:
    global _default
    if _default is None:
        _default = E5Embedder()
    return _default


def _get_model() -> TextEmbedding:
    global _model
    if _model is None:
        os.environ.setdefault(ENV_MODEL_CACHE, str(model_cache_dir()))
        _register_model()
        from fastembed import TextEmbedding

        _model = TextEmbedding(model_name=MODEL_NAME)
    return _model


def _register_model() -> None:
    global _registered
    if _registered:
        return
    from fastembed import TextEmbedding
    from fastembed.common.model_description import ModelSource, PoolingType

    try:
        TextEmbedding.add_custom_model(
            model=MODEL_NAME,
            pooling=PoolingType.MEAN,
            normalization=True,
            sources=ModelSource(hf=MODEL_NAME),
            dim=EMBEDDING_DIM,
            model_file=MODEL_FILE,
            description="intfloat multilingual-e5-small",
            license=MODEL_LICENSE,
            size_in_gb=MODEL_SIZE_GB,
        )
    except ValueError as exc:
        if ALREADY_REGISTERED not in str(exc):
            raise
    _registered = True
