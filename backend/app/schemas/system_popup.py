from datetime import datetime
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field, field_validator, model_validator


class PopupType(str, Enum):
    ANNOUNCEMENT = "announcement"
    ACCOUNT = "account"
    REVIEW = "review"
    INTERACTION = "interaction"


class PopupSendMode(str, Enum):
    IMMEDIATE = "immediate"
    ONCE = "once"
    REPEAT = "repeat"
    APP_START = "app_start"


class PopupTaskStatus(str, Enum):
    DRAFT = "draft"
    SCHEDULED = "scheduled"
    RUNNING = "running"
    PAUSED = "paused"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class PopupTargetMode(str, Enum):
    ALL = "all"
    USER_IDS = "user_ids"
    FILTER = "filter"


class PopupRepeatType(str, Enum):
    DAILY = "daily"
    WEEKLY = "weekly"
    MONTHLY = "monthly"


class SystemPopupTargetIn(BaseModel):
    target_mode: PopupTargetMode = PopupTargetMode.ALL
    target_user_ids: list[int] | str | None = None
    target_filters: dict[str, Any] | None = None


class SystemPopupTaskCreateIn(SystemPopupTargetIn):
    title: str = Field(..., min_length=1, max_length=50)
    content: str = Field(..., min_length=1)
    type: PopupType
    send_mode: PopupSendMode = PopupSendMode.IMMEDIATE
    status: PopupTaskStatus = PopupTaskStatus.DRAFT
    publish_at: datetime | None = None
    repeat_type: PopupRepeatType | None = None
    repeat_time: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    repeat_weekday: int | None = Field(default=None, ge=0, le=6)
    repeat_month_day: int | None = Field(default=None, ge=1, le=31)
    start_at: datetime | None = None
    end_at: datetime | None = None
    max_runs: int | None = Field(default=None, ge=1)

    @field_validator("title", "content")
    @classmethod
    def strip_text(cls, value: str) -> str:
        return value.strip()

    @model_validator(mode="after")
    def validate_repeat_end_condition(self) -> "SystemPopupTaskCreateIn":
        if self.send_mode == PopupSendMode.REPEAT and self.end_at is None and self.max_runs is None:
            raise ValueError("周期重复必须填写结束时间或最大发送次数")
        return self


class SystemPopupTaskUpdateIn(SystemPopupTaskCreateIn):
    id: int = Field(..., ge=1)


class SystemPopupTaskActionIn(BaseModel):
    id: int = Field(..., ge=1)


class SystemPopupEstimateIn(SystemPopupTargetIn):
    pass


class SystemPopupAckOut(BaseModel):
    ok: bool = True


class SystemPopupStartupIn(BaseModel):
    launch_id: str = Field(..., min_length=1, max_length=48)

    @field_validator("launch_id")
    @classmethod
    def strip_launch_id(cls, value: str) -> str:
        return value.strip()
