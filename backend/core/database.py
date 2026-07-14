from __future__ import annotations

import json
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from .models import Plan, PlanRecord


def _parse_date(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    if not isinstance(value, str):
        return None
    text = value.strip()
    if not text:
        return None
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        try:
            return datetime.fromisoformat(f"{text}T00:00:00+00:00")
        except ValueError:
            return None


def _parse_deadline(value: Any, fallback: str) -> str:
    if value is None:
        return fallback
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return fallback
        parsed = _parse_date(text)
        if parsed is not None:
            return parsed.date().isoformat()
        if len(text) >= 10 and text[4] == "-" and text[7] == "-":
            return text[:10]
    return fallback


def _priority_rank(priority: Any) -> int:
    value = str(priority or "").strip().lower()
    if value == "high":
        return 0
    if value == "medium":
        return 1
    if value == "low":
        return 2
    return 3


def _sort_tasks(tasks: list[dict[str, Any]]) -> list[dict[str, Any]]:
    def sort_key(task: dict[str, Any]) -> tuple[Any, ...]:
        deadline = _parse_date(task.get("deadline"))
        recorded_at = _parse_date(task.get("recorded_at"))
        deadline_key = deadline or datetime.max.replace(tzinfo=timezone.utc)
        recorded_key = recorded_at or datetime.max.replace(tzinfo=timezone.utc)
        return (
            deadline_key,
            _priority_rank(task.get("priority")),
            recorded_key,
            int(task.get("id", 0) or 0),
        )

    return sorted(tasks, key=sort_key)


def _normalize_task(task: dict[str, Any], fallback_deadline: str, recorded_at: str) -> dict[str, Any]:
    task_copy = dict(task)
    task_copy["id"] = int(task_copy.get("id", 0) or 0)
    task_copy["title"] = str(task_copy.get("title", "")).strip()
    task_copy["description"] = str(task_copy.get("description", "")).strip()
    task_copy["priority"] = str(task_copy.get("priority", "low")).strip().lower() or "low"
    if task_copy["priority"] not in {"high", "medium", "low"}:
        task_copy["priority"] = "low"

    estimated_min = task_copy.get("estimated_min", task_copy.get("estimatedMin", 15))
    try:
        task_copy["estimated_min"] = max(1, int(estimated_min or 15))
    except (TypeError, ValueError):
        task_copy["estimated_min"] = 15

    raw_tags = task_copy.get("tags", [])
    if isinstance(raw_tags, list):
        tags = [str(tag).strip().lower() for tag in raw_tags if str(tag).strip()]
    else:
        tags = []
    task_copy["tags"] = list(dict.fromkeys(tags))

    scheduled_at = task_copy.get("scheduled_at")
    task_copy["scheduled_at"] = str(scheduled_at).strip() if scheduled_at else None
    task_copy["deadline"] = _parse_deadline(
        task_copy.get("deadline") or task_copy.get("date") or scheduled_at,
        fallback_deadline,
    )
    task_copy["recorded_at"] = str(task_copy.get("recorded_at") or recorded_at).strip() or recorded_at
    task_copy["status"] = str(task_copy.get("status", "pending")).strip().lower() or "pending"
    if task_copy["status"] not in {"pending", "done"}:
        task_copy["status"] = "pending"
    task_copy.pop("date", None)
    task_copy.pop("estimatedMin", None)
    return task_copy


def append_plan_history_file(
    file_path: str | Path,
    plan_id: int,
    raw_text: str,
    plan: Plan,
    period: str,
    status: str = "completed",
) -> Path:
    path = Path(file_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    created_at = plan.created_at.astimezone(timezone.utc)
    fallback_deadline = (created_at + timedelta(days=3)).date().isoformat()
    recorded_at = created_at.isoformat()

    payload = plan.model_dump(mode="json")
    tasks = payload.get("tasks", [])
    normalized_tasks: list[dict[str, Any]] = []
    if isinstance(tasks, list):
        for item in tasks:
            if isinstance(item, dict):
                normalized_tasks.append(_normalize_task(item, fallback_deadline, recorded_at))
    normalized_tasks = _sort_tasks(normalized_tasks)

    payload["tasks"] = normalized_tasks
    payload["recorded_at"] = recorded_at
    payload["created_at"] = recorded_at

    record = {
        "id": int(plan_id),
        "raw_text": str(raw_text),
        "structured_plan": payload,
        "notes": plan.notes,
        "created_at": recorded_at,
        "period": str(period),
        "status": status,
    }

    existing: list[dict[str, Any]] = []
    if path.exists():
        try:
            loaded = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(loaded, list):
                existing = [item for item in loaded if isinstance(item, dict)]
            elif isinstance(loaded, dict):
                existing = [loaded]
        except json.JSONDecodeError:
            existing = []

    existing.append(record)
    path.write_text(json.dumps(existing, ensure_ascii=False, indent=2), encoding="utf-8")
    return path


class Database:
    def __init__(self, db_path: str) -> None:
        self.db_path = Path(db_path)
        self.create_table_if_not_exists()

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        return connection

    def create_table_if_not_exists(self) -> None:
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        with self._connect() as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS plans (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    raw_text TEXT NOT NULL,
                    structured_plan TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    period TEXT NOT NULL,
                    status TEXT NOT NULL
                )
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_plans_created_at
                ON plans(created_at DESC)
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_plans_period
                ON plans(period)
                """
            )
            conn.execute(
                """
                CREATE INDEX IF NOT EXISTS idx_plans_status
                ON plans(status)
                """
            )

    @staticmethod
    def _normalize_search_value(value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip().lower()
        return normalized or None

    @staticmethod
    def _safe_plan_payload(raw_plan: Any) -> dict[str, Any]:
        if isinstance(raw_plan, str):
            payload = json.loads(raw_plan)
        elif isinstance(raw_plan, dict):
            payload = raw_plan
        else:
            raise TypeError("structured_plan must be a JSON object")

        if not isinstance(payload, dict):
            raise TypeError("structured_plan must be a JSON object")

        tasks = payload.get("tasks", [])
        if not isinstance(tasks, list):
            tasks = []

        normalized_tasks: list[dict[str, Any]] = []
        base_created_at = _parse_date(payload.get("recorded_at") or payload.get("created_at"))
        if base_created_at is None:
            base_created_at = datetime.now(timezone.utc)
        fallback_deadline = (base_created_at + timedelta(days=3)).date().isoformat()
        recorded_at = base_created_at.isoformat()

        for task in tasks:
            if not isinstance(task, dict):
                continue
            normalized_tasks.append(_normalize_task(task, fallback_deadline, recorded_at))

        payload = dict(payload)
        payload["tasks"] = _sort_tasks(normalized_tasks)
        payload["recorded_at"] = recorded_at
        payload["created_at"] = recorded_at
        return payload

    @staticmethod
    def _row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
        record = PlanRecord(
            id=int(row["id"]),
            raw_text=row["raw_text"],
            structured_plan=json.loads(row["structured_plan"]),
            created_at=datetime.fromisoformat(row["created_at"]),
            period=row["period"],
            status=row["status"],
        )
        data = record.model_dump(mode="json")
        data["structured_plan"] = Database._safe_plan_payload(data["structured_plan"])
        return data

    def _fetch_row(self, plan_id: int) -> sqlite3.Row | None:
        with self._connect() as conn:
            return conn.execute(
                """
                SELECT id, raw_text, structured_plan, created_at, period, status
                FROM plans
                WHERE id = ?
                """,
                (plan_id,),
            ).fetchone()

    def save_plan(self, raw_text: str, plan: Plan, period: str) -> int:
        plan_payload = plan.model_dump(mode="json")
        created_at = plan.created_at.astimezone(timezone.utc)
        fallback_deadline = (created_at + timedelta(days=3)).date().isoformat()
        recorded_at = created_at.isoformat()

        tasks = plan_payload.get("tasks", [])
        normalized_tasks: list[dict[str, Any]] = []
        if isinstance(tasks, list):
            for task in tasks:
                if isinstance(task, dict):
                    normalized_tasks.append(_normalize_task(task, fallback_deadline, recorded_at))
        normalized_tasks = _sort_tasks(normalized_tasks)

        plan_payload["tasks"] = normalized_tasks
        plan_payload["recorded_at"] = recorded_at
        plan_payload["created_at"] = recorded_at

        structured_plan = json.dumps(plan_payload, ensure_ascii=False)
        with self._connect() as conn:
            cursor = conn.execute(
                """
                INSERT INTO plans (raw_text, structured_plan, created_at, period, status)
                VALUES (?, ?, ?, ?, ?)
                """,
                (raw_text, structured_plan, recorded_at, period, "completed"),
            )
            return int(cursor.lastrowid)

    def replace_plan(self, plan_id: int, raw_text: str, plan: Plan) -> bool:
        existing = self._fetch_row(plan_id)
        if existing is None:
            return False
        created_at = plan.created_at.astimezone(timezone.utc)
        recorded_at = created_at.isoformat()
        fallback_deadline = (created_at + timedelta(days=3)).date().isoformat()
        payload = plan.model_dump(mode="json")
        raw_tasks = payload.get("tasks", [])
        payload["tasks"] = _sort_tasks(
            [
                _normalize_task(task, fallback_deadline, recorded_at)
                for task in raw_tasks
                if isinstance(task, dict)
            ]
        )
        payload["recorded_at"] = recorded_at
        payload["created_at"] = recorded_at
        with self._connect() as conn:
            cursor = conn.execute(
                """
                UPDATE plans
                SET raw_text = ?, structured_plan = ?
                WHERE id = ?
                """,
                (raw_text, json.dumps(payload, ensure_ascii=False), plan_id),
            )
            return cursor.rowcount > 0

    def list_plans(
        self,
        limit: int = 20,
        offset: int = 0,
        search: str | None = None,
        tag: str | None = None,
    ) -> list[dict[str, Any]]:
        clauses: list[str] = []
        params: list[Any] = []

        normalized_search = self._normalize_search_value(search)
        normalized_tag = self._normalize_search_value(tag)

        if normalized_search:
            pattern = f"%{normalized_search}%"
            clauses.append(
                """
                (
                    LOWER(raw_text) LIKE ?
                    OR LOWER(structured_plan) LIKE ?
                    OR LOWER(period) LIKE ?
                    OR LOWER(status) LIKE ?
                )
                """
            )
            params.extend([pattern, pattern, pattern, pattern])

        if normalized_tag:
            clauses.append("LOWER(structured_plan) LIKE ?")
            params.append(f'%"{normalized_tag}"%')

        where_clause = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        query = f"""
            SELECT id, raw_text, structured_plan, created_at, period, status
            FROM plans
            {where_clause}
            ORDER BY created_at DESC, id DESC
            LIMIT ? OFFSET ?
        """
        params.extend([limit, offset])

        with self._connect() as conn:
            rows = conn.execute(query, params).fetchall()
        return [self._row_to_dict(row) for row in rows]

    def get_plan(self, plan_id: int) -> dict[str, Any] | None:
        row = self._fetch_row(plan_id)
        if row is None:
            return None
        return self._row_to_dict(row)

    def get_plan_with_tasks(self, plan_id: int) -> dict[str, Any] | None:
        row = self._fetch_row(plan_id)
        if row is None:
            return None
        return self._row_to_dict(row)

    def update_task_status(self, plan_id: int, task_id: int, status: str) -> bool:
        normalized_status = status.strip().lower()
        if normalized_status not in {"pending", "done"}:
            raise ValueError("status must be 'pending' or 'done'")

        row = self._fetch_row(plan_id)
        if row is None:
            return False

        payload = self._safe_plan_payload(row["structured_plan"])
        tasks = payload.get("tasks", [])
        if not isinstance(tasks, list):
            return False

        updated = False
        for task in tasks:
            if isinstance(task, dict) and int(task.get("id", -1)) == task_id:
                task["status"] = normalized_status
                updated = True
                break

        if not updated:
            return False

        payload["tasks"] = _sort_tasks([task for task in tasks if isinstance(task, dict)])

        with self._connect() as conn:
            cursor = conn.execute(
                """
                UPDATE plans
                SET structured_plan = ?
                WHERE id = ?
                """,
                (json.dumps(payload, ensure_ascii=False), plan_id),
            )
            return cursor.rowcount > 0

    def delete_plan(self, plan_id: int) -> bool:
        with self._connect() as conn:
            cursor = conn.execute("DELETE FROM plans WHERE id = ?", (plan_id,))
            return cursor.rowcount > 0

    def clear_all(self) -> int:
        with self._connect() as conn:
            cursor = conn.execute("DELETE FROM plans")
            return int(cursor.rowcount)
