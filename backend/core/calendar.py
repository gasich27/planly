from __future__ import annotations

from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from uuid import uuid4

from icalendar import Calendar, Event

from .database import Database


def _normalize_task_status(value: Any) -> str:
    if isinstance(value, str):
        status = value.strip().lower()
        if status in {"pending", "done"}:
            return status
    return "pending"


def export_to_ics(plan_id: int, db_path: str, output_path: str) -> str:
    db = Database(db_path)
    plan = db.get_plan_with_tasks(plan_id)
    if plan is None:
        raise ValueError(f"План с ID {plan_id} не найден")

    structured_plan = plan.get("structured_plan", {})
    if not isinstance(structured_plan, dict):
        raise ValueError("План имеет некорректную структуру")

    tasks = structured_plan.get("tasks", [])
    if not isinstance(tasks, list):
        raise ValueError("Задачи плана имеют некорректный формат")

    calendar = Calendar()
    calendar.add("prodid", "-//AI Planner//ru//")
    calendar.add("version", "2.0")
    calendar.add("calscale", "GREGORIAN")

    now = datetime.now(timezone.utc)

    for task in tasks:
        if not isinstance(task, dict):
            continue

        task_id = int(task.get("id", 0) or 0)
        title = str(task.get("title", f"Task {task_id}"))
        estimated_min = int(task.get("estimated_min", 30) or 30)
        status = _normalize_task_status(task.get("status"))

        event = Event()
        event.add("uid", f"plan-{plan_id}-task-{task_id}-{uuid4().hex}@ai-planner")
        event.add("summary", title)
        event.add("dtstamp", now)
        event.add("dtstart", now)
        event.add("dtend", now + timedelta(minutes=estimated_min))
        event.add("status", "CONFIRMED" if status == "done" else "TENTATIVE")
        event.add("description", f"Plan ID: {plan_id}; Task ID: {task_id}; Status: {status}")
        calendar.add_component(event)

    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(calendar.to_ical())
    return str(output)
