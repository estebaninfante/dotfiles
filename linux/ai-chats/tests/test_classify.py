from __future__ import annotations

from ai_chats.classify import classify_platform


def test_url_field_wins() -> None:
    content = "url: https://chatgpt.com/c/123\n\nhola\n"
    assert classify_platform("archivo.md", content) == "ChatGPT"


def test_service_field_alias() -> None:
    content = "service: Claude\n\nhola\n"
    assert classify_platform("archivo.md", content) == "Claude"


def test_filename_signal() -> None:
    content = " conversacion sobre grok y mas grok otra vez grok\n"
    assert classify_platform("notas-de-grok-2026.md", content) == "Grok"


def test_body_signal_without_url() -> None:
    content = "empecemos con chatgpt, luego openai y de nuevo chatgpt\n"
    assert classify_platform("archivo.md", content) == "ChatGPT"


def test_deepseek_signal() -> None:
    content = "deepseek r1 y deepseek v3 son modelos\n"
    assert classify_platform("archivo.md", content) == "DeepSeek"


def test_gemini_signal() -> None:
    content = "gemini responde rapido, probemos gemini otra vez\n"
    assert classify_platform("archivo.md", content) == "Gemini"


def test_fallback_varios() -> None:
    content = "receta de tortilla de patatas con cebolla\n"
    assert classify_platform("archivo.md", content) == "Varios"


def test_url_beats_body_noise() -> None:
    content = "url: https://claude.ai/chat/9\n\nhoy hablamos de grok y grok\n"
    assert classify_platform("archivo.md", content) == "Claude"
