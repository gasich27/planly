from __future__ import annotations

import json
import os
import re
from datetime import datetime, timezone
from typing import Any

from openai import APIConnectionError, BadRequestError, InternalServerError, OpenAI, RateLimitError
from pydantic import ValidationError
from rich import print as rprint
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from .config import Settings
from .models import Plan


def _fallback_plan(error_message: str) -> Plan:
    return Plan(
        title="План не создан",
        tasks=[],
        notes=f"Ошибка валидации или разбора ответа модели: {error_message}",
        created_at=datetime.now(timezone.utc),
    )


def _extract_json_payload(content: str) -> str:
    text = content.strip()
    if not text:
        raise ValueError("Пустой ответ LLM")

    match = re.search(r"```json\s*([\s\S]*?)```|(\{[\s\S]*\})", text)
    if match:
        payload = match.group(1) or match.group(2) or ""
        payload = payload.strip()
        if payload:
            return payload

    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end != -1 and end > start:
        return text[start : end + 1].strip()

    raise ValueError("Не удалось извлечь JSON из ответа модели")


def _log_retry_attempt(retry_state: Any) -> None:
    attempt_number = getattr(retry_state, "attempt_number", 1)
    outcome = getattr(retry_state, "outcome", None)
    error = None
    if outcome is not None and callable(getattr(outcome, "exception", None)):
        error = outcome.exception()
    rprint(f"[yellow]Попытка LLM #{attempt_number} завершилась ошибкой: {error}[/yellow]")


@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=2, max=10),
    retry=retry_if_exception_type(
        (RateLimitError, APIConnectionError, BadRequestError, InternalServerError)
    ),
    before_sleep=_log_retry_attempt,
    reraise=True,
)
def _request_plan_content(text: str, period: str, settings: Settings) -> str:
    client = OpenAI(base_url=settings.api_base, api_key=settings.api_key)
    model_name = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
    today_utc = datetime.now(timezone.utc).date().isoformat()

    system_prompt = (
        "Ты строгий ассистент-планировщик задач. "
        "По входному тексту и периоду планирования создай практичный и реалистичный план. "
        "Верни только чистый JSON без markdown, без пояснений и без лишних символов. "
        "Структура ответа строго такая: "
        '{"title": str, "created_at": "YYYY-MM-DDTHH:MM:SSZ", "tasks": [{"id": int, "title": str, "priority": "high"|"medium"|"low", "estimated_min": int, "tags": [string], "deadline": "YYYY-MM-DD"|null, "recorded_at": "YYYY-MM-DDTHH:MM:SSZ"|null}], "notes": str}. '
        "title — короткое название общего плана; tasks — список конкретных задач в логическом порядке; "
        "id — последовательные целые числа, начиная с 1; title каждой задачи — глагольная и понятная формулировка. "
        "priority используй так: high для срочного или критически важного, medium для обычного, low для второстепенного. "
        "estimated_min — реалистичная оценка в минутах, только целое число больше нуля. "
        "tags — 2-5 коротких меток по смыслу задачи, например: анализ, текст, код, проверка, запуск, исправление, документация. "
        "deadline — дата дедлайна в формате YYYY-MM-DD; если дедлайн не сказан, ставь null. "
        "recorded_at — время записи в UTC ISO-формате, если известно. "
        f"Текущая дата для отсчёта дедлайнов: {today_utc}. "
        "notes — краткое резюме того, что именно было понято из запроса и на что обратить внимание. "
        "Если данных мало, всё равно верни максимально полезный минимальный план. "
        "Располагаи задачи внутри ответа по строгой иерархии: сначала ближайший deadline, затем важность high, medium, low. "
        "Теги должны быть массивом строк, не одной строкой и не null."
    )

    user_prompt = (
        f"Период планирования: {period}\n"
        f"Дата записи: {today_utc}\n"
        f"Входной текст:\n{text}\n\n"
        "Сформируй JSON по заданной схеме. "
        "Если в речи есть дедлайн, используй его для deadline. "
        "Если дедлайн не был назван, ставь deadline null. "
        "Не сваливай все задачи в одну дату, если в тексте есть несколько сроков."
    )

    response = client.chat.completions.create(
        model=model_name,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ],
        temperature=0.2,
    )
    return response.choices[0].message.content or ""


def generate_plan(text: str, period: str, settings: Settings) -> Plan:
    try:
        content = _request_plan_content(text, period, settings)
        payload_text = _extract_json_payload(content)
        payload = json.loads(payload_text)
        return Plan.model_validate(payload)
    except (json.JSONDecodeError, ValueError, ValidationError) as exc:
        return _fallback_plan(str(exc))
    except Exception:
        raise
