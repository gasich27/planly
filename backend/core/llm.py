from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from pydantic import ValidationError
from rich import print as rprint
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from .config import Settings
from .models import Plan


class OllamaError(RuntimeError):
    pass


def _fallback_plan(error_message: str) -> Plan:
    return Plan(
        title="План не создан",
        tasks=[],
        notes=f"Ответ Ollama не удалось разобрать: {error_message}",
        created_at=datetime.now(timezone.utc),
    )


def _extract_json_payload(content: str) -> str:
    text = content.strip()
    if not text:
        raise ValueError("Ollama вернул пустой ответ")

    match = re.search(r"```json\s*([\s\S]*?)```|(\{[\s\S]*\})", text)
    if match:
        payload = (match.group(1) or match.group(2) or "").strip()
        if payload:
            return payload

    start = text.find("{")
    end = text.rfind("}")
    if start != -1 and end > start:
        return text[start : end + 1].strip()
    raise ValueError("В ответе Ollama нет JSON-объекта")


def _log_retry_attempt(retry_state: Any) -> None:
    outcome = getattr(retry_state, "outcome", None)
    error = outcome.exception() if outcome is not None else None
    rprint(
        f"[yellow]Попытка Ollama #{retry_state.attempt_number} завершилась ошибкой: {error}[/yellow]"
    )


def _prompt(text: str, period: str) -> tuple[str, str]:
    now = datetime.now(timezone.utc)
    today = now.date().isoformat()
    system = (
        "Ты AI-планировщик PLANLY. Преобразуй запрос пользователя в практичный план. "
        "Верни только JSON без markdown. Схема: "
        '{"title": str, "created_at": "ISO-8601 UTC", "tasks": ['
        '{"id": int, "title": str, "description": str, "priority": "high"|"medium"|"low", '
        '"estimated_min": int, "tags": [str], "deadline": "YYYY-MM-DD"|null, '
        '"scheduled_at": "ISO-8601 with timezone"|null, '
        '"recorded_at": "ISO-8601 UTC", "status": "pending"}], "notes": str}. '
        "Названия задач должны быть короткими и начинаться с действия. description — одно короткое уточняющее предложение. "
        "Для каждой задачи выбери реалистичный приоритет и 1-3 коротких тега. "
        "Учитывай относительные даты: сегодня, завтра, через неделю. "
        "Если запрос содержит разные дни, распредели задачи по соответствующим deadline. "
        "Если пользователь называет время, обязательно запиши его в scheduled_at. "
        "Если дата не названа, используй текущую дату. Не выдумывай задачи вне запроса."
    )
    user = (
        f"Текущая дата UTC: {today}\n"
        f"Период интерфейса: {period}\n"
        f"Время создания: {now.isoformat()}\n"
        f"Команда пользователя:\n{text}"
    )
    return system, user


@retry(
    stop=stop_after_attempt(3),
    wait=wait_exponential(multiplier=1, min=1, max=5),
    retry=retry_if_exception_type((OllamaError, URLError, TimeoutError)),
    before_sleep=_log_retry_attempt,
    reraise=True,
)
def _request_plan_content(text: str, period: str, settings: Settings) -> str:
    system_prompt, user_prompt = _prompt(text, period)
    payload = json.dumps(
        {
            "model": settings.ollama_model,
            "stream": False,
            "format": "json",
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "options": {"temperature": 0.2},
        },
        ensure_ascii=False,
    ).encode("utf-8")
    endpoint = f"{settings.ollama_base_url.rstrip('/')}/api/chat"
    request = Request(
        endpoint,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=120) as response:
            body = json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise OllamaError(f"Ollama HTTP {exc.code}: {detail}") from exc
    except (URLError, TimeoutError):
        raise
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise OllamaError(f"Некорректный ответ Ollama: {exc}") from exc

    message = body.get("message") if isinstance(body, dict) else None
    content = message.get("content") if isinstance(message, dict) else None
    if not isinstance(content, str) or not content.strip():
        raise OllamaError("Ollama не вернул message.content")
    return content


def generate_plan(text: str, period: str, settings: Settings) -> Plan:
    try:
        content = _request_plan_content(text, period, settings)
        payload = json.loads(_extract_json_payload(content))
        return Plan.model_validate(payload)
    except (json.JSONDecodeError, ValueError, ValidationError) as exc:
        return _fallback_plan(str(exc))


def revise_plan(plan_payload: dict[str, Any], instruction: str, settings: Settings) -> Plan:
    current = json.dumps(plan_payload, ensure_ascii=False)
    command = (
        "Измени существующий план по команде пользователя. Сохрани все задачи и поля, "
        "которых команда не касается. Не добавляй посторонние задачи.\n"
        f"Текущий план: {current}\n"
        f"Команда изменения: {instruction}"
    )
    return generate_plan(command, "revision", settings)
