from __future__ import annotations

import html
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, HTMLResponse

from .calendar import export_to_ics
from .config import get_settings
from .database import Database
from .models import Plan


app = FastAPI(title="AI Planner")


def _format_datetime(value: object) -> str:
    if isinstance(value, datetime):
        dt = value
    elif isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value)
        except ValueError:
            return html.escape(value)
    else:
        return "-"

    if dt.tzinfo is not None:
        dt = dt.astimezone()
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def _safe_text(value: Any) -> str:
    if value is None:
        return ""
    return html.escape(str(value))


def _task_counts(tasks: list[Any]) -> tuple[int, int]:
    done = 0
    pending = 0
    for task in tasks:
        if isinstance(task, dict):
            status = str(task.get("status", "pending")).strip().lower()
        else:
            status = "pending"
        if status == "done":
            done += 1
        else:
            pending += 1
    return done, pending


def _load_db() -> Database:
    settings = get_settings()
    return Database(settings.db_path)


def _render_page(title: str, body: str) -> HTMLResponse:
    html_page = f"""<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{html.escape(title)}</title>
</head>
<body style="font-family: Arial, sans-serif; margin: 24px; background: #f7f7f5; color: #1b1b1b;">
  <div style="max-width: 1100px; margin: 0 auto;">
    <h1 style="margin-bottom: 16px;">{html.escape(title)}</h1>
    {body}
  </div>
</body>
</html>"""
    return HTMLResponse(content=html_page)


@app.get("/", response_class=HTMLResponse)
def index() -> HTMLResponse:
    db = _load_db()
    plans = db.list_plans(limit=200)

    rows: list[str] = []
    for plan in plans:
        structured = plan.get("structured_plan", {})
        if isinstance(structured, dict):
            plan_title = str(structured.get("title", "-"))
            tasks = structured.get("tasks", [])
            if not isinstance(tasks, list):
                tasks = []
        else:
            plan_title = "-"
            tasks = []

        done, pending = _task_counts(tasks)
        rows.append(
            f"""
            <tr>
              <td style="padding: 10px; border-bottom: 1px solid #ddd;">{plan.get("id", "-")}</td>
              <td style="padding: 10px; border-bottom: 1px solid #ddd;">{_safe_text(_format_datetime(plan.get("created_at")))}</td>
              <td style="padding: 10px; border-bottom: 1px solid #ddd;"><a href="/plan/{plan.get("id", 0)}">{_safe_text(plan_title)}</a></td>
              <td style="padding: 10px; border-bottom: 1px solid #ddd;">{len(tasks)}</td>
              <td style="padding: 10px; border-bottom: 1px solid #ddd;">✅ {done} / ⬜ {pending}</td>
            </tr>
            """
        )

    table = f"""
    <table style="width: 100%; border-collapse: collapse; background: white; border-radius: 12px; overflow: hidden;">
      <thead>
        <tr style="background: #eceae4;">
          <th style="text-align: left; padding: 12px;">ID</th>
          <th style="text-align: left; padding: 12px;">Дата</th>
          <th style="text-align: left; padding: 12px;">Заголовок</th>
          <th style="text-align: left; padding: 12px;">Задач</th>
          <th style="text-align: left; padding: 12px;">Статус задач</th>
        </tr>
      </thead>
      <tbody>
        {''.join(rows) if rows else '<tr><td colspan="5" style="padding: 16px;">Планы пока не найдены.</td></tr>'}
      </tbody>
    </table>
    """

    body = f"""
    <div style="margin-bottom: 16px;">
      <a href="/" style="text-decoration: none; color: #444;">Обновить</a>
    </div>
    {table}
    """
    return _render_page("AI Planner — Планы", body)


@app.get("/plan/{plan_id}", response_class=HTMLResponse)
def plan_detail(plan_id: int) -> HTMLResponse:
    db = _load_db()
    plan = db.get_plan_with_tasks(plan_id)
    if plan is None:
        raise HTTPException(status_code=404, detail="Plan not found")

    structured = plan.get("structured_plan", {})
    if not isinstance(structured, dict):
        raise HTTPException(status_code=500, detail="Invalid plan structure")

    plan_model = Plan.model_validate(structured)
    tasks_html: list[str] = []
    for task in plan_model.tasks:
        checked = "checked" if task.status == "done" else ""
        label_style = "text-decoration: line-through; color: #666;" if task.status == "done" else "color: #1b1b1b;"
        tasks_html.append(
            f"""
            <li style="margin-bottom: 10px; list-style: none; padding: 12px; background: #fff; border: 1px solid #ddd; border-radius: 10px;">
              <label style="{label_style}">
                <input type="checkbox" {checked} disabled style="margin-right: 8px;" />
                <strong>{_safe_text(task.title)}</strong>
                <span style="color: #666;">({task.priority}, {task.estimated_min} мин, {', '.join(task.tags) if task.tags else 'без тегов'})</span>
                <div style="margin-top: 6px; font-size: 13px; color: #555;">Статус: {task.status}</div>
              </label>
            </li>
            """
        )

    body = f"""
    <div style="display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 16px;">
      <a href="/" style="text-decoration: none; color: #444;">← Назад</a>
      <a href="/export/{plan_id}/ics" style="text-decoration: none; color: #0b5;">Скачать .ics</a>
    </div>
    <div style="background: #fff; border: 1px solid #ddd; border-radius: 12px; padding: 16px; margin-bottom: 16px;">
      <h2 style="margin-top: 0;">{_safe_text(plan_model.title)}</h2>
      <div style="color: #555; margin-bottom: 8px;">ID: {plan.get("id", "-")} | Период: {_safe_text(plan.get("period", "-"))} | Статус: {_safe_text(plan.get("status", "-"))}</div>
      <div style="color: #555; margin-bottom: 8px;">Создан: {_safe_text(_format_datetime(plan.get("created_at")))}</div>
      <p style="line-height: 1.6;">{_safe_text(plan_model.notes)}</p>
    </div>
    <div style="background: #fff; border: 1px solid #ddd; border-radius: 12px; padding: 16px; margin-bottom: 16px;">
      <h3 style="margin-top: 0;">Задачи</h3>
      <ul style="padding-left: 0; margin: 0;">
        {''.join(tasks_html) if tasks_html else '<li>Задачи не найдены.</li>'}
      </ul>
    </div>
    <div style="background: #fff; border: 1px solid #ddd; border-radius: 12px; padding: 16px;">
      <h3 style="margin-top: 0;">Исходный текст</h3>
      <p style="white-space: pre-wrap; line-height: 1.6;">{_safe_text(plan.get("raw_text", ""))}</p>
    </div>
    """
    return _render_page(f"План #{plan_id}", body)


@app.get("/export/{plan_id}/ics")
def export_plan_ics(plan_id: int) -> FileResponse:
    settings = get_settings()
    temp_dir = Path(tempfile.gettempdir())
    output_path = temp_dir / f"ai_planner_plan_{plan_id}.ics"
    exported = export_to_ics(plan_id=plan_id, db_path=settings.db_path, output_path=str(output_path))
    path = Path(exported)
    if not path.exists():
        raise HTTPException(status_code=500, detail="ICS export failed")
    return FileResponse(
        path,
        media_type="text/calendar",
        filename=path.name,
    )


def run_web() -> None:
    uvicorn.run(app, host="127.0.0.1", port=8000, log_level="info")
