from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


class Task(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: int = Field(ge=1)
    title: str = Field(min_length=1)
    priority: Literal["high", "medium", "low"]
    estimated_min: int = Field(ge=1)
    tags: list[str] = Field(default_factory=list)
    deadline: str | None = None
    recorded_at: datetime | None = None
    status: Literal["pending", "done"] = "pending"

    @field_validator("title", mode="before")
    @classmethod
    def normalize_title(cls, value: Any) -> str:
        if not isinstance(value, str):
            raise TypeError("title must be a string")
        text = value.strip()
        if not text:
            raise ValueError("title must not be empty")
        return text

    @field_validator("priority", mode="before")
    @classmethod
    def normalize_priority(cls, value: Any) -> str:
        if not isinstance(value, str):
            raise TypeError("priority must be a string")
        priority = value.strip().lower()
        if not priority:
            raise ValueError("priority must not be empty")
        return priority

    @field_validator("estimated_min", mode="before")
    @classmethod
    def normalize_estimated_min(cls, value: Any) -> int:
        if isinstance(value, bool):
            raise TypeError("estimated_min must be a positive integer")
        try:
            minutes = int(value)
        except (TypeError, ValueError) as exc:
            raise TypeError("estimated_min must be a positive integer") from exc
        if minutes <= 0:
            raise ValueError("estimated_min must be greater than zero")
        return minutes

    @field_validator("tags", mode="before")
    @classmethod
    def normalize_tags(cls, value: Any) -> list[str]:
        if value is None or value == "":
            return []

        tags: list[str] = []
        raw_items: list[Any]

        if isinstance(value, str):
            raw_items = [item for item in value.split(",")]
        elif isinstance(value, list):
            raw_items = value
        else:
            return []

        for item in raw_items:
            if not isinstance(item, str):
                continue
            tag = item.strip().lower()
            if tag and tag not in tags:
                tags.append(tag)
        return tags

    @field_validator("deadline", mode="before")
    @classmethod
    def normalize_deadline(cls, value: Any) -> str | None:
        if value is None or value == "":
            return None
        if not isinstance(value, str):
            raise TypeError("deadline must be a string")
        text = value.strip()
        return text or None

    @field_validator("recorded_at", mode="before")
    @classmethod
    def normalize_recorded_at(cls, value: Any) -> datetime | None:
        if value is None or value == "":
            return None
        if isinstance(value, datetime):
            return value
        if not isinstance(value, str):
            raise TypeError("recorded_at must be a datetime string")
        text = value.strip()
        if not text:
            return None
        try:
            return datetime.fromisoformat(text.replace("Z", "+00:00"))
        except ValueError as exc:
            raise ValueError("recorded_at must be ISO formatted") from exc

    @field_validator("status", mode="before")
    @classmethod
    def normalize_status(cls, value: Any) -> str:
        if value is None or value == "":
            return "pending"
        if not isinstance(value, str):
            raise TypeError("status must be a string")
        status = value.strip().lower()
        if not status:
            return "pending"
        if status not in {"pending", "done"}:
            return "pending"
        return status


class Plan(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str = Field(min_length=1)
    tasks: list[Task] = Field(default_factory=list)
    notes: str = Field(min_length=1)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    @field_validator("title", "notes", mode="before")
    @classmethod
    def normalize_text(cls, value: Any) -> str:
        if not isinstance(value, str):
            raise TypeError("value must be a string")
        text = value.strip()
        if not text:
            raise ValueError("text must not be empty")
        return text


class PlanRecord(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: int = Field(ge=1)
    raw_text: str
    structured_plan: dict[str, Any]
    created_at: datetime
    period: str
    status: str

    @field_validator("raw_text", "period", "status", mode="before")
    @classmethod
    def normalize_record_text(cls, value: Any) -> str:
        if not isinstance(value, str):
            raise TypeError("value must be a string")
        text = value.strip()
        if not text:
            raise ValueError("value must not be empty")
        return text

    @field_validator("structured_plan", mode="before")
    @classmethod
    def normalize_structured_plan(cls, value: Any) -> dict[str, Any]:
        if isinstance(value, dict):
            return value
        if isinstance(value, str):
            loaded = json.loads(value)
            if isinstance(loaded, dict):
                return loaded
        raise TypeError("structured_plan must be a JSON object")
