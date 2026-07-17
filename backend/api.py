from __future__ import annotations

import asyncio
import json
import tempfile
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from time import perf_counter
from typing import Literal

import uvicorn
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from core.stt import transcribe_audio
from core.llm import generate_plan, revise_plan
from core.database import Database, append_plan_history_file
from core.calendar import export_to_ics
from core.config import get_settings


settings = get_settings()
db = Database(settings.db_path)

app = FastAPI(title="AI Planner API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class PlanRequest(BaseModel):
    text: str = Field(min_length=1)
    period: str = Field(default="day")


class TaskStatusRequest(BaseModel):
    status: Literal["pending", "done"]


class AiEditRequest(BaseModel):
    instruction: str = Field(min_length=1)


def _task_date(task: dict[str, object], fallback: date) -> date:
    value = task.get("scheduled_at") or task.get("deadline") or task.get("date")
    if isinstance(value, str) and value.strip():
        try:
            return date.fromisoformat(value.strip()[:10])
        except ValueError:
            pass
    return fallback


def _context_range(context: str, today: date) -> tuple[date, date]:
    normalized = context.strip().lower()
    if normalized == "tomorrow":
        tomorrow = today + timedelta(days=1)
        return tomorrow, tomorrow
    if normalized == "week":
        return today, today + timedelta(days=6)
    if normalized == "month":
        if today.month == 12:
            next_month = date(today.year + 1, 1, 1)
        else:
            next_month = date(today.year, today.month + 1, 1)
        return today, next_month - timedelta(days=1)
    return today, today


def _build_dashboard(context: str, selected_date: date | None = None) -> dict[str, object]:
    today = datetime.now().astimezone().date()
    start, end = _context_range(context, selected_date or today)
    plans = db.list_plans(limit=500, offset=0)
    tasks: list[dict[str, object]] = []

    for plan in plans:
        structured = plan.get("structured_plan")
        if not isinstance(structured, dict):
            continue
        created_value = plan.get("created_at")
        try:
            fallback = datetime.fromisoformat(str(created_value).replace("Z", "+00:00")).date()
        except ValueError:
            fallback = today
        raw_tasks = structured.get("tasks")
        if not isinstance(raw_tasks, list):
            continue
        for raw_task in raw_tasks:
            if not isinstance(raw_task, dict):
                continue
            scheduled = _task_date(raw_task, fallback)
            if not start <= scheduled <= end:
                continue
            task = dict(raw_task)
            task["plan_id"] = int(plan.get("id", 0) or 0)
            task["plan_title"] = str(structured.get("title", ""))
            task["deadline"] = scheduled.isoformat()
            tasks.append(task)

    total = len(tasks)
    completed = sum(1 for task in tasks if str(task.get("status", "pending")) == "done")
    percentage = round((completed / total) * 100) if total else 0
    priority_rank = {"high": 0, "medium": 1, "low": 2}
    pending = [task for task in tasks if str(task.get("status", "pending")) != "done"]
    pending.sort(
        key=lambda task: (
            priority_rank.get(str(task.get("priority", "low")).lower(), 3),
            str(task.get("deadline", "")),
            int(task.get("id", 0) or 0),
        )
    )
    estimated_minutes = sum(int(task.get("estimated_min", 0) or 0) for task in tasks)
    focus_start = "09:00"
    scheduled_hours: list[int] = []
    for task in tasks:
        scheduled_at = task.get("scheduled_at")
        if isinstance(scheduled_at, str) and "T" in scheduled_at:
            try:
                scheduled_hours.append(datetime.fromisoformat(scheduled_at.replace("Z", "+00:00")).hour)
            except ValueError:
                pass
    if scheduled_hours:
        focus_start = f"{min(scheduled_hours):02d}:00"
    focus_hour = int(focus_start[:2])
    focus_end = f"{min(focus_hour + 3, 23):02d}:00"
    high_priority = sum(
        1 for task in tasks if str(task.get("priority", "low")).lower() == "high"
    )
    break_minutes = 15 if estimated_minutes >= 120 else 10
    if not tasks:
        summary = "No plan has been created for this day yet."
        personal_tip = "Add your first task and PLANLY will build a focused schedule."
    else:
        summary = f"{len(tasks)} tasks planned, with {high_priority} high-priority focus items."
        personal_tip = (
            "Start with the highest-priority task while your energy is fresh."
            if high_priority
            else "Group similar tasks together to keep your momentum."
        )
    return {
        "context": context.strip().lower() or "today",
        "date": start.isoformat(),
        "range_end": end.isoformat(),
        "percentage": percentage,
        "completed": completed,
        "total": total,
        "priority_tasks": pending[:3],
        "summary": summary,
        "focus_start": focus_start,
        "focus_end": focus_end,
        "main_tasks": min(len(pending), 3),
        "break_minutes": break_minutes,
        "personal_tip": personal_tip,
    }


def _json_error(error: str, detail: str, status_code: int) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content={
            "error": error,
            "detail": detail,
        },
    )


def _normalize_period(value: str) -> str:
    return str(value).lower().strip() or "day"


def _normalize_output_filename(name: str, default_suffix: str) -> str:
    path = Path(name.strip() if name else "")
    if path.suffix:
        return str(path)
    return str(path.with_suffix(default_suffix))


def _load_latest_plan_from_file() -> dict[str, object]:
    plan_path = Path(__file__).with_name("plan.json")
    if not plan_path.exists():
        raise FileNotFoundError(f"{plan_path} not found")

    raw_text = plan_path.read_text(encoding="utf-8")
    payload = json.loads(raw_text)

    if isinstance(payload, list):
        if not payload:
            raise ValueError("plan.json is empty")
        latest = payload[-1]
        if isinstance(latest, dict):
            return latest
        raise TypeError("latest plan entry must be an object")

    if not isinstance(payload, dict):
        raise TypeError("plan.json must contain a JSON object or list of objects")

    tasks = payload.get("tasks", [])
    normalized_tasks: list[dict[str, object]] = []
    if isinstance(tasks, list):
        for index, task in enumerate(tasks, start=1):
            if not isinstance(task, dict):
                continue
            raw_tags = task.get("tags", [])
            if isinstance(raw_tags, list):
                tags = [str(tag).strip() for tag in raw_tags if str(tag).strip()]
            else:
                tags = []
            normalized_tasks.append(
                {
                    "id": int(task.get("id", index)),
                    "title": str(task.get("title", "")).strip(),
                    "description": str(task.get("description", "")).strip(),
                    "priority": str(task.get("priority", "low")).strip().lower(),
                    "estimated_min": int(task.get("estimated_min", task.get("estimatedMin", 15)) or 15),
                    "status": "pending",
                    "tags": tags,
                    "date": str(task.get("date")).strip() if task.get("date") else None,
                    "scheduled_at": str(task.get("scheduled_at")).strip() if task.get("scheduled_at") else None,
                }
            )

    title = str(payload.get("title", "Today plan")).strip()
    notes = str(payload.get("notes", "")).strip()
    created_at_value = payload.get("created_at")
    if isinstance(created_at_value, str) and created_at_value.strip():
        created_at = created_at_value.strip()
    else:
        created_at = datetime.now(timezone.utc).isoformat()

    return {
        "id": 1,
        "title": title,
        "raw_text": title,
        "structured_plan": {
            "title": title,
            "tasks": normalized_tasks,
            "notes": notes,
            "created_at": created_at,
        },
        "notes": notes,
        "created_at": created_at,
        "period": "day",
    }


# curl -X POST "http://127.0.0.1:8000/api/transcribe" -F "audio=@sample.mp3"
@app.post("/api/transcribe")
async def api_transcribe(audio: UploadFile = File(...)) -> JSONResponse:
    temp_path: Path | None = None
    try:
        started = perf_counter()
        data = await audio.read()
        if not data:
            raise ValueError("Uploaded audio file is empty")

        suffix = Path(audio.filename or "audio.tmp").suffix or ".tmp"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(data)
            temp_path = Path(tmp.name)

        text = await asyncio.to_thread(transcribe_audio, str(temp_path), settings)
        duration_sec = round(perf_counter() - started, 3)
        return JSONResponse(
            content={
                "text": text,
                "duration_sec": duration_sec,
            }
        )
    except (ValueError, FileNotFoundError, TypeError) as exc:
        return _json_error("transcribe_error", str(exc), 400)
    except Exception as exc:
        return _json_error("transcribe_error", str(exc), 500)
    finally:
        try:
            await audio.close()
        except Exception:
            pass
        if temp_path is not None:
            try:
                temp_path.unlink(missing_ok=True)
            except Exception:
                pass


# curl -X POST "http://127.0.0.1:8000/api/plan" -H "Content-Type: application/json" -d "{\"text\":\"Сделай план на день\", \"period\":\"day\"}"
@app.post("/api/plan")
async def api_plan(payload: PlanRequest) -> JSONResponse:
    try:
        text = str(payload.text).strip()
        period = _normalize_period(payload.period)
        if not text:
            raise ValueError("text must not be empty")

        plan: Plan = await asyncio.to_thread(generate_plan, text, period, settings)
        plan_id = await asyncio.to_thread(db.save_plan, text, plan, period)
        await asyncio.to_thread(
            append_plan_history_file,
            Path(__file__).with_name("plan.json"),
            plan_id,
            text,
            plan,
            period,
        )

        content = plan.model_dump(mode="json")
        content["id"] = plan_id
        content["period"] = period
        return JSONResponse(content=content)
    except (ValueError, TypeError) as exc:
        return _json_error("plan_error", str(exc), 400)
    except Exception as exc:
        return _json_error("plan_error", str(exc), 500)


# curl "http://127.0.0.1:8000/api/plans?limit=20&offset=0"
@app.get("/api/plans")
async def api_list_plans(
    limit: int = 20,
    offset: int = 0,
    tag: str | None = None,
    search: str | None = None,
) -> JSONResponse:
    try:
        plans = await asyncio.to_thread(
            db.list_plans,
            limit,
            offset,
            search,
            tag,
        )
        return JSONResponse(content={"items": plans, "limit": limit, "offset": offset})
    except (ValueError, TypeError) as exc:
        return _json_error("list_error", str(exc), 400)
    except Exception as exc:
        return _json_error("list_error", str(exc), 500)


# curl "http://127.0.0.1:8000/api/latest-plan"
@app.get("/api/latest-plan")
async def api_latest_plan() -> JSONResponse:
    try:
        plan = await asyncio.to_thread(_load_latest_plan_from_file)
        return JSONResponse(content=plan)
    except Exception as exc:
        return _json_error("latest_plan_error", str(exc), 500)


# curl "http://127.0.0.1:8000/api/dashboard?context=today"
@app.get("/api/dashboard")
async def api_dashboard(
    context: str = "today", date_value: str | None = None
) -> JSONResponse:
    try:
        if context.strip().lower() not in {"today", "tomorrow", "week", "month"}:
            raise ValueError("context must be today, tomorrow, week or month")
        selected_date = date.fromisoformat(date_value) if date_value else None
        dashboard = await asyncio.to_thread(_build_dashboard, context, selected_date)
        return JSONResponse(content=dashboard)
    except (ValueError, TypeError) as exc:
        return _json_error("dashboard_error", str(exc), 400)
    except Exception as exc:
        return _json_error("dashboard_error", str(exc), 500)


# curl "http://127.0.0.1:8000/api/plans/1"
@app.get("/api/plans/{plan_id}")
async def api_get_plan(plan_id: int) -> JSONResponse:
    try:
        plan = await asyncio.to_thread(db.get_plan_with_tasks, plan_id)
        if plan is None:
            return _json_error("not_found", f"Plan {plan_id} not found", 404)
        return JSONResponse(content=plan)
    except (ValueError, TypeError) as exc:
        return _json_error("plan_error", str(exc), 400)
    except Exception as exc:
        return _json_error("plan_error", str(exc), 500)


# curl -X PATCH "http://127.0.0.1:8000/api/tasks/1/2/status" -H "Content-Type: application/json" -d "{\"status\":\"done\"}"
@app.patch("/api/tasks/{plan_id}/{task_id}/status")
async def api_update_task_status(plan_id: int, task_id: int, payload: TaskStatusRequest) -> JSONResponse:
    try:
        updated = await asyncio.to_thread(db.update_task_status, plan_id, task_id, payload.status)
        if not updated:
            return _json_error("not_found", f"Task {task_id} in plan {plan_id} not found", 404)

        plan = await asyncio.to_thread(db.get_plan_with_tasks, plan_id)
        return JSONResponse(
            content={
                "ok": True,
                "plan_id": plan_id,
                "task_id": task_id,
                "status": payload.status,
                "plan": plan,
            }
        )
    except (ValueError, TypeError) as exc:
        return _json_error("status_error", str(exc), 400)
    except Exception as exc:
        return _json_error("status_error", str(exc), 500)


# curl -X POST "http://127.0.0.1:8000/api/plans/1/ai-edit" -H "Content-Type: application/json" -d "{\"instruction\":\"Move task 2 to tomorrow\"}"
@app.post("/api/plans/{plan_id}/ai-edit")
async def api_ai_edit_plan(plan_id: int, payload: AiEditRequest) -> JSONResponse:
    try:
        current = await asyncio.to_thread(db.get_plan_with_tasks, plan_id)
        if current is None:
            return _json_error("not_found", f"Plan {plan_id} not found", 404)
        structured = current.get("structured_plan")
        if not isinstance(structured, dict):
            raise ValueError("Plan has invalid structured data")
        revised = await asyncio.to_thread(
            revise_plan,
            structured,
            payload.instruction.strip(),
            settings,
        )
        if structured.get("tasks") and not revised.tasks:
            raise ValueError(revised.notes)
        updated = await asyncio.to_thread(
            db.replace_plan,
            plan_id,
            f"{current.get('raw_text', '')}\nAI edit: {payload.instruction.strip()}",
            revised,
        )
        if not updated:
            return _json_error("not_found", f"Plan {plan_id} not found", 404)
        result = await asyncio.to_thread(db.get_plan_with_tasks, plan_id)
        return JSONResponse(content=result)
    except (ValueError, TypeError) as exc:
        return _json_error("ai_edit_error", str(exc), 400)
    except Exception as exc:
        return _json_error("ai_edit_error", str(exc), 500)


# curl -L "http://127.0.0.1:8000/api/export/1/ics" -o plan.ics
@app.get("/api/export/{plan_id}/ics", response_model=None)
async def api_export_ics(plan_id: int):
    try:
        output_name = _normalize_output_filename(f"plan_{plan_id}.ics", ".ics")
        output_path = Path(tempfile.gettempdir()) / output_name
        exported = await asyncio.to_thread(
            export_to_ics,
            plan_id,
            settings.db_path,
            str(output_path),
        )
        path = Path(exported)
        if not path.exists():
            return _json_error("export_error", "ICS file was not created", 500)
        return FileResponse(
            path,
            media_type="text/calendar",
            filename=path.name,
        )
    except (ValueError, TypeError) as exc:
        return _json_error("export_error", str(exc), 400)
    except Exception as exc:
        return _json_error("export_error", str(exc), 500)


if __name__ == "__main__":
    uvicorn.run("api:app", host="0.0.0.0", port=8000, reload=True)
