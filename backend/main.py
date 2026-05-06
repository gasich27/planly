from __future__ import annotations

import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

import typer
from rich import print as rprint
from rich.box import ROUNDED
from rich.console import Console
from rich.panel import Panel
from rich.progress import BarColumn, Progress, SpinnerColumn, TaskProgressColumn, TextColumn, TimeElapsedColumn
from rich.table import Table
from rich.text import Text

from core import Database, Plan, Task, generate_plan, get_settings, transcribe_audio
from core.database import append_plan_history_file
from core.calendar import export_to_ics
from core.web import run_web


console = Console()
app = typer.Typer(add_completion=False, no_args_is_help=True, help="AI planner CLI")


def _format_datetime(value: object) -> str:
    if isinstance(value, datetime):
        dt = value
    elif isinstance(value, str):
        try:
            dt = datetime.fromisoformat(value)
        except ValueError:
            return value
    else:
        return "-"

    if dt.tzinfo is not None:
        dt = dt.astimezone()
    return dt.strftime("%Y-%m-%d %H:%M:%S")


def _task_status_value(task: Any) -> str:
    if hasattr(task, "status"):
        value = getattr(task, "status")
    elif isinstance(task, dict):
        value = task.get("status", "pending")
    else:
        value = "pending"

    status = str(value).strip().lower()
    if status == "done":
        return "done"
    return "pending"


def _task_status_label(status: str) -> str:
    return "✅ done" if status == "done" else "⬜ pending"


def _task_counts(tasks: list[Any]) -> tuple[int, int]:
    done = 0
    pending = 0
    for task in tasks:
        if _task_status_value(task) == "done":
            done += 1
        else:
            pending += 1
    return done, pending


def _build_tasks_table(tasks: list[Task], title: str = "Задачи") -> Table:
    table = Table(title=title, box=ROUNDED, show_lines=True)
    table.add_column("ID", style="cyan", no_wrap=True)
    table.add_column("Статус", style="white", no_wrap=True)
    table.add_column("Приоритет", style="white", no_wrap=True)
    table.add_column("Задача", style="white")
    table.add_column("Мин", style="magenta", no_wrap=True)
    table.add_column("Теги", style="green")

    priority_styles = {
        "high": "bold red",
        "medium": "yellow",
        "low": "green",
    }

    for task in tasks:
        status = _task_status_value(task)
        table.add_row(
            str(task.id),
            _task_status_label(status),
            Text(task.priority, style=priority_styles.get(task.priority, "white")),
            task.title,
            str(task.estimated_min),
            ", ".join(task.tags) if task.tags else "-",
        )

    return table


def _build_history_table(records: list[dict[str, object]], title: str = "История планов") -> Table:
    table = Table(title=title, box=ROUNDED, show_lines=False)
    table.add_column("ID", style="cyan", no_wrap=True)
    table.add_column("Дата", style="white", no_wrap=True)
    table.add_column("Заголовок", style="white")
    table.add_column("Задач", style="magenta", justify="right", no_wrap=True)
    table.add_column("Статус задач", style="green", no_wrap=True)
    table.add_column("Период", style="green", no_wrap=True)

    for record in records:
        structured_plan = record.get("structured_plan")
        plan_title = "-"
        tasks: list[Any] = []
        if isinstance(structured_plan, dict):
            plan_title = str(structured_plan.get("title", "-"))
            raw_tasks = structured_plan.get("tasks", [])
            if isinstance(raw_tasks, list):
                tasks = raw_tasks

        done, pending = _task_counts(tasks)
        table.add_row(
            str(record.get("id", "-")),
            _format_datetime(record.get("created_at")),
            plan_title,
            str(len(tasks)),
            f"✅ {done} / ⬜ {pending}",
            str(record.get("period", "-")),
        )

    return table


def _print_plan_details(record: dict[str, object]) -> None:
    structured_plan = record.get("structured_plan")
    if not isinstance(structured_plan, dict):
        raise ValueError("План поврежден: structured_plan имеет неверный формат")

    plan = Plan.model_validate(structured_plan)
    console.print(
        Panel(
            f"[bold]{plan.title}[/bold]\n"
            f"ID: {record.get('id', '-')}\n"
            f"Период: {record.get('period', '-')}\n"
            f"Статус: {record.get('status', '-')}\n"
            f"Создан: {_format_datetime(record.get('created_at'))}",
            box=ROUNDED,
            title="План",
            border_style="cyan",
        )
    )
    console.print(_build_tasks_table(plan.tasks, title="Задачи плана"))
    console.print(
        Panel(
            plan.notes,
            box=ROUNDED,
            title="Заметки",
            border_style="green",
        )
    )
    console.print(
        Panel(
            record.get("raw_text", "-"),
            box=ROUNDED,
            title="Исходный текст",
            border_style="yellow",
        )
    )


def _require_confirmation(confirm: bool, prompt: str) -> bool:
    if confirm:
        return True
    if sys.stdin.isatty():
        return typer.confirm(prompt, default=False)
    rprint("[yellow]Операция отменена. Используйте `--yes`, если хотите подтвердить действие.[/yellow]")
    return False


def _export_plan(output: str, plan_id: int, raw_text: str, period: str, plan: Plan) -> Path:
    output_path = Path(output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    existing: list[dict[str, object]] = []
    if output_path.exists():
        try:
            loaded = json.loads(output_path.read_text(encoding="utf-8"))
            if isinstance(loaded, list):
                existing = [item for item in loaded if isinstance(item, dict)]
            elif isinstance(loaded, dict):
                existing = [loaded]
        except json.JSONDecodeError:
            existing = []

    if plan_id <= 0:
        plan_id = len(existing) + 1

    append_plan_history_file(output_path, plan_id, raw_text, plan, period)
    return output_path


@app.command()
def process(
    file: str = typer.Argument(..., help="Путь к аудиофайлу"),
    period: str = typer.Option("day", help="Период планирования"),
    output: str = typer.Option("plan.json", help="Путь для экспорта JSON"),
) -> None:
    try:
        period = str(period).lower().strip()
        output = str(output).strip()

        settings = get_settings()
        db = Database(settings.db_path)

        with Progress(
            SpinnerColumn(style="cyan"),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(bar_width=None),
            TaskProgressColumn(),
            TimeElapsedColumn(),
            console=console,
            transient=True,
        ) as progress:
            stt_task = progress.add_task("Распознавание речи", total=1)
            transcript = transcribe_audio(file, settings)
            progress.update(stt_task, completed=1)

            llm_task = progress.add_task("Генерация плана", total=1)
            plan = generate_plan(transcript, period, settings)
            progress.update(llm_task, completed=1)

            save_task = progress.add_task("Сохранение и экспорт", total=1)
            plan_id = db.save_plan(transcript, plan, period)
            exported_path = _export_plan(output, plan_id, transcript, period, plan)
            progress.update(save_task, completed=1)

        record = db.get_plan(plan_id)
        if record is None:
            raise RuntimeError("План был сохранен, но не найден в базе данных")

        console.print(
            Panel(
                f"[bold green]План создан и сохранён[/bold green]\n"
                f"ID: {plan_id}\n"
                f"Файл: {exported_path}\n"
                f"Период: {period}",
                box=ROUNDED,
                border_style="green",
                title="Готово",
            )
        )
        console.print(_build_history_table([record], title="Последний план"))
        console.print(_build_tasks_table(plan.tasks))
    except Exception as exc:
        rprint(f"[bold red]{exc}[/bold red]")
        raise typer.Exit(code=1)


@app.command(name="list")
def list_plans(
    limit: int = typer.Option(10, help="Количество записей"),
    search: str | None = typer.Option(None, help="Поиск по тексту или JSON"),
    tag: str | None = typer.Option(None, help="Фильтр по тегу"),
) -> None:
    try:
        if limit < 1:
            raise ValueError("limit должен быть больше нуля")

        settings = get_settings()
        db = Database(settings.db_path)
        records = db.list_plans(limit=limit, search=search, tag=tag)

        if not records:
            rprint("[yellow]История планов пуста.[/yellow]")
            return

        console.print(_build_history_table(records))
    except Exception as exc:
        rprint(f"[bold red]{exc}[/bold red]")
        raise typer.Exit(code=1)


@app.command()
def show(plan_id: int) -> None:
    try:
        settings = get_settings()
        db = Database(settings.db_path)
        record = db.get_plan(plan_id)
        if record is None:
            rprint(f"[yellow]План с ID {plan_id} не найден.[/yellow]")
            raise typer.Exit(code=1)

        _print_plan_details(record)
    except typer.Exit:
        raise
    except Exception as exc:
        rprint(f"[bold red]{exc}[/bold red]")
        raise typer.Exit(code=1)


@app.command()
def delete(
    plan_id: int,
    confirm: bool = typer.Option(False, "--yes", help="Подтвердить удаление"),
) -> None:
    try:
        settings = get_settings()
        db = Database(settings.db_path)
        record = db.get_plan(plan_id)
        if record is None:
            rprint(f"[yellow]План с ID {plan_id} не найден.[/yellow]")
            raise typer.Exit(code=1)

        if not _require_confirmation(confirm, f"Удалить план #{plan_id}?"):
            return

        if db.delete_plan(plan_id):
            rprint(f"[green]План #{plan_id} удалён.[/green]")
        else:
            rprint(f"[yellow]Не удалось удалить план #{plan_id}.[/yellow]")
            raise typer.Exit(code=1)
    except typer.Exit:
        raise
    except Exception as exc:
        rprint(f"[bold red]{exc}[/bold red]")
        raise typer.Exit(code=1)


@app.command()
def clear(
    confirm: bool = typer.Option(False, "--yes", help="Подтвердить очистку"),
) -> None:
    try:
        settings = get_settings()
        db = Database(settings.db_path)

        if not _require_confirmation(confirm, "Очистить всю историю планов?"):
            return

        deleted = db.clear_all()
        rprint(f"[green]Удалено записей: {deleted}[/green]")
    except typer.Exit:
        raise
    except Exception as exc:
        rprint(f"[bold red]{exc}[/bold red]")
        raise typer.Exit(code=1)


@app.command()
def done(plan_id: int, task_id: int) -> None:
    try:
        settings = get_settings()
        db = Database(settings.db_path)
        updated = db.update_task_status(plan_id, task_id, "done")
        if updated:
            rprint(f"[green]Задача {task_id} в плане {plan_id} отмечена выполненной.[/green]")
        else:
            rprint(f"[yellow]Не удалось обновить задачу {task_id} в плане {plan_id}.[/yellow]")
            raise typer.Exit(code=1)
    except Exception as exc:
        rprint(f"[bold red]{exc}[/bold red]")
        raise typer.Exit(code=1)


@app.command()
def export(plan_id: int, output: str = typer.Option("plan.ics", help="Путь для файла .ics")) -> None:
    try:
        settings = get_settings()
        output_path = str(output).strip()
        exported = export_to_ics(plan_id=plan_id, db_path=settings.db_path, output_path=output_path)
        rprint(f"[green]ICS экспортирован: {exported}[/green]")
    except Exception as exc:
        rprint(f"[bold red]{exc}[/bold red]")
        raise typer.Exit(code=1)


@app.command()
def web() -> None:
    try:
        run_web()
    except Exception as exc:
        rprint(f"[bold red]{exc}[/bold red]")
        raise typer.Exit(code=1)


def _run_cli() -> None:
    if len(sys.argv) == 2 and not sys.argv[1].startswith("-") and Path(sys.argv[1]).exists():
        process(file=sys.argv[1], period="day", output="plan.json")
        return
    app()


if __name__ == "__main__":
    _run_cli()
