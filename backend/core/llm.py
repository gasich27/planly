from __future__ import annotations

import json
import re
from datetime import date, datetime, timezone
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


def _prompt(
    text: str,
    period: str,
    target_date: str | None = None,
) -> tuple[str, str]:
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
    system += (
        " CRITICAL: preserve every distinct action from the user request as a separate task. "
        "If the user lists N actions, return N task objects. Never merge unrelated actions. "
        "Commas, semicolons, numbered items, new lines, and conjunctions may separate tasks. "
        "Do not omit, summarize, or replace requested actions."
    )
    if target_date:
        system += (
            f" TARGET_DATE={target_date} is mandatory and overrides every date in the user text. "
            "Set deadline to TARGET_DATE for every task. For scheduled_at, preserve the requested "
            "time but use TARGET_DATE as the calendar date."
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
def _request_plan_content(
    text: str,
    period: str,
    settings: Settings,
    target_date: str | None = None,
) -> str:
    system_prompt, user_prompt = _prompt(text, period, target_date)
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


def generate_plan(
    text: str,
    period: str,
    settings: Settings,
    target_date: str | None = None,
) -> Plan:
    try:
        content = _request_plan_content(text, period, settings, target_date)
        payload = json.loads(_extract_json_payload(content))
        plan = Plan.model_validate(payload)
        if target_date:
            selected_date = date.fromisoformat(target_date)
            for task in plan.tasks:
                task.deadline = selected_date.isoformat()
                if task.scheduled_at is not None:
                    task.scheduled_at = task.scheduled_at.replace(
                        year=selected_date.year,
                        month=selected_date.month,
                        day=selected_date.day,
                    )
        return plan
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
