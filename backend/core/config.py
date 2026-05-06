from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
import os

from dotenv import load_dotenv


load_dotenv()


@dataclass(slots=True, frozen=True)
class Settings:
    api_base: str
    api_key: str
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
        api_base=_read_setting("OPENAI_API_BASE", "http://127.0.0.1:1234/v1"),
        api_key=_read_setting("OPENAI_API_KEY", "dummy"),
        whisper_model=_read_setting("WHISPER_MODEL", "base"),
        whisper_language=_read_setting("WHISPER_LANGUAGE", "ru"),
        db_path=_read_setting("DB_PATH", "planner.db"),
    )
