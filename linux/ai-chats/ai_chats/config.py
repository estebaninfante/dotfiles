from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

PLATFORMS: tuple[str, ...] = ("ChatGPT", "Claude", "Gemini", "Grok", "DeepSeek", "Varios")
FALLBACK_PLATFORM = "Varios"
MODEL_NAME = "intfloat/multilingual-e5-small"
EMBEDDING_DIM = 384

DEFAULT_ROOT = "~/ai-chats"
DEFAULT_STAGING = "~/Downloads/AIChats"
DEFAULT_MODEL_CACHE = "~/.cache/fastembed"
ENV_ROOT = "AI_CHATS_ROOT"
ENV_STAGING = "AI_CHATS_STAGING"
ENV_MODEL_CACHE = "FASTEMBED_CACHE_PATH"


@dataclass(frozen=True)
class Paths:
    root: Path
    staging: Path

    @property
    def db_path(self) -> Path:
        return self.root / "chats.sqlite"

    @property
    def lock_path(self) -> Path:
        return self.root / ".lock"

    def platform_dir(self, platform: str) -> Path:
        if platform not in PLATFORMS:
            raise ValueError(f"plataforma desconocida: {platform}")
        return self.root / platform

    def destination(self, platform: str, filename: str) -> Path:
        directory = self.platform_dir(platform)
        candidate = directory / filename
        if not candidate.exists():
            return candidate
        stem = filename.removesuffix(".md")
        counter = 2
        while True:
            candidate = directory / f"{stem}-{counter}.md"
            if not candidate.exists():
                return candidate
            counter += 1

    @classmethod
    def default(cls) -> Paths:
        root = Path(os.environ.get(ENV_ROOT, DEFAULT_ROOT)).expanduser()
        staging = Path(os.environ.get(ENV_STAGING, DEFAULT_STAGING)).expanduser()
        return cls(root=root, staging=staging)


def model_cache_dir() -> Path:
    return Path(os.environ.get(ENV_MODEL_CACHE, DEFAULT_MODEL_CACHE)).expanduser()


def ensure_layout(paths: Paths) -> None:
    paths.root.mkdir(parents=True, exist_ok=True)
    paths.staging.mkdir(parents=True, exist_ok=True)
