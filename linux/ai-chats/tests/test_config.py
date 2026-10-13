from __future__ import annotations

from pathlib import Path

import pytest

from ai_chats.config import ENV_ROOT, ENV_STAGING, Paths, ensure_layout


def _paths(tmp_path: Path) -> Paths:
    return Paths(root=tmp_path / "store", staging=tmp_path / "staging")


def test_destination_free(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    assert paths.destination("ChatGPT", "chat.md") == paths.root / "ChatGPT" / "chat.md"


def test_destination_suffixes_collisions(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    directory = paths.platform_dir("ChatGPT")
    directory.mkdir(parents=True)
    (directory / "chat.md").write_text("uno", encoding="utf-8")
    assert paths.destination("ChatGPT", "chat.md") == directory / "chat-2.md"
    (directory / "chat-2.md").write_text("dos", encoding="utf-8")
    assert paths.destination("ChatGPT", "chat.md") == directory / "chat-3.md"


def test_platform_dir_rejects_unknown(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    with pytest.raises(ValueError):
        paths.platform_dir("Otra")


def test_ensure_layout_creates_dirs(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    ensure_layout(paths)
    assert paths.root.is_dir()
    assert paths.staging.is_dir()


def test_default_paths_read_env(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    monkeypatch.setenv(ENV_ROOT, str(tmp_path / "raiz"))
    monkeypatch.setenv(ENV_STAGING, str(tmp_path / "staging"))
    paths = Paths.default()
    assert paths.root == tmp_path / "raiz"
    assert paths.staging == tmp_path / "staging"
    assert paths.db_path == tmp_path / "raiz" / "chats.sqlite"
    assert paths.lock_path == tmp_path / "raiz" / ".lock"
