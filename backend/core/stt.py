from __future__ import annotations

from functools import lru_cache
import re
from pathlib import Path

from faster_whisper import WhisperModel

from .config import Settings


@lru_cache(maxsize=1)
def _load_model(model_name: str) -> WhisperModel:
    return WhisperModel(model_name, device="cpu", compute_type="int8")


def transcribe_audio(file_path: str, settings: Settings) -> str:
    try:
        audio_path = Path(file_path)
        if not audio_path.exists():
            raise FileNotFoundError(f"Файл не найден: {audio_path}")
        if not audio_path.is_file():
            raise ValueError(f"Это не файл: {audio_path}")

        model = _load_model(settings.whisper_model)
        segments, _info = model.transcribe(
            str(audio_path),
            language=settings.whisper_language,
        )

        parts: list[str] = []
        for segment in segments:
            text = segment.text.strip()
            if text:
                parts.append(text)

        transcript = re.sub(r"\s+", " ", " ".join(parts)).strip()
        if not transcript:
            raise ValueError("Транскрипция вернула пустой текст")
        return transcript
    except Exception as exc:
        raise RuntimeError(f"Ошибка STT: {exc}") from exc
