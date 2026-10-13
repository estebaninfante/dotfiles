from __future__ import annotations

import re

from .config import FALLBACK_PLATFORM, PLATFORMS

URL_PATTERN = re.compile(r"^url\s*:\s*(\S+)", re.IGNORECASE | re.MULTILINE)
FIELD_PATTERN = re.compile(
    r"^(?:platform|service|source|site)\s*:\s*(.+)$", re.IGNORECASE | re.MULTILINE
)
TITLE_PATTERN = re.compile(r"^title\s*:\s*(.+)$", re.IGNORECASE | re.MULTILINE)

URL_MARKERS: tuple[tuple[str, str], ...] = (
    ("chatgpt.com", "ChatGPT"),
    ("chat.openai.com", "ChatGPT"),
    ("openai.com", "ChatGPT"),
    ("claude.ai", "Claude"),
    ("anthropic.com", "Claude"),
    ("gemini.google.com", "Gemini"),
    ("aistudio.google", "Gemini"),
    ("chat.deepseek.com", "DeepSeek"),
    ("deepseek.com", "DeepSeek"),
    ("grok.com", "Grok"),
    ("x.ai", "Grok"),
)

FIELD_ALIASES: tuple[tuple[str, str], ...] = (
    ("chatgpt", "ChatGPT"),
    ("openai", "ChatGPT"),
    ("claude", "Claude"),
    ("anthropic", "Claude"),
    ("gemini", "Gemini"),
    ("grok", "Grok"),
    ("xai", "Grok"),
    ("deepseek", "DeepSeek"),
)

KEYWORDS: dict[str, tuple[str, ...]] = {
    "ChatGPT": ("chatgpt", "openai", "gpt-4", "gpt-5", "gpt4"),
    "Claude": ("claude", "anthropic"),
    "Gemini": ("gemini",),
    "Grok": ("grok", "xai", "x.ai"),
    "DeepSeek": ("deepseek", "deep seek"),
}

HEAD_CHARS = 6000
TITLE_WEIGHT = 4
SCORE_THRESHOLD = 2


def classify_platform(filename: str, content: str) -> str:
    url_match = URL_PATTERN.search(content)
    if url_match is not None:
        hit = _platform_from_url(url_match.group(1))
        if hit is not None:
            return hit
    field_match = FIELD_PATTERN.search(content)
    if field_match is not None:
        hit = _platform_from_field(field_match.group(1))
        if hit is not None:
            return hit
    title_match = TITLE_PATTERN.search(content)
    title = title_match.group(1) if title_match is not None else ""
    return _best_by_score(filename, title, content)


def _platform_from_url(url: str) -> str | None:
    lowered = url.lower()
    for marker, platform in URL_MARKERS:
        if marker in lowered:
            return platform
    return None


def _platform_from_field(value: str) -> str | None:
    lowered = value.lower()
    for alias, platform in FIELD_ALIASES:
        if alias in lowered:
            return platform
    return None


def _best_by_score(filename: str, title: str, content: str) -> str:
    scores = _scores(filename, title, content)
    best = FALLBACK_PLATFORM
    best_score = 0
    for platform in PLATFORMS:
        if platform == FALLBACK_PLATFORM:
            continue
        score = scores.get(platform, 0)
        if score > best_score:
            best = platform
            best_score = score
    return best if best_score >= SCORE_THRESHOLD else FALLBACK_PLATFORM


def _scores(filename: str, title: str, content: str) -> dict[str, int]:
    head = content[:HEAD_CHARS].lower()
    name_text = f"{filename} {title}".lower()
    scores: dict[str, int] = {}
    for platform, keywords in KEYWORDS.items():
        title_hits = sum(keyword in name_text for keyword in keywords)
        head_hits = sum(head.count(keyword) for keyword in keywords)
        scores[platform] = title_hits * TITLE_WEIGHT + head_hits
    return scores
