from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
import os

from dotenv import load_dotenv


load_dotenv()


@dataclass(slots=True, frozen=True)
class Settings:
    ollama_base_url: str
    ollama_model: str
    ollama_models_dir: str
    whisper_model: str
    whisper_language: str
    db_path: str


def _read_setting(name: str, default: str) -> str:
    value = os.getenv(name, default).strip()
    return value or default


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    load_dotenv()
    return Settings(
        ollama_base_url=_read_setting("OLLAMA_BASE_URL", "http://127.0.0.1:11434"),
        ollama_model=_read_setting("OLLAMA_MODEL", "qwen2.5:7b"),
        ollama_models_dir=_read_setting("OLLAMA_MODELS", "D:/Ollama/Models"),
        whisper_model=_read_setting("WHISPER_MODEL", "base"),
        whisper_language=_read_setting("WHISPER_LANGUAGE", "ru"),
        db_path=_read_setting("DB_PATH", "planner.db"),
    )
