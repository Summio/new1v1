from datetime import datetime
from enum import Enum
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator


class NotificationType(str, Enum):
    ANNOUNCEMENT = "announcement"
    ACCOUNT = "account"
    REVIEW = "review"
    INTERACTION = "interaction"


class NotificationSendMode(str, Enum):
    IMMEDIATE = "immediate"
    ONCE = "once"
    REPEAT = "repeat"


class NotificationTaskStatus(str, Enum):
    DRAFT = "draft"
    SCHEDULED = "scheduled"
    RUNNING = "running"
    PAUSED = "paused"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class NotificationTargetMode(str, Enum):
    ALL = "all"
    USER_IDS = "user_ids"
    FILTER = "filter"


class NotificationRepeatType(str, Enum):
    DAILY = "daily"
    WEEKLY = "weekly"
    MONTHLY = "monthly"


class NotificationTargetIn(BaseModel):
    target_mode: NotificationTargetMode = NotificationTargetMode.ALL
    target_user_ids: list[int] | str | None = None
    target_filters: dict[str, Any] | None = None


class SystemNotificationTaskCreateIn(NotificationTargetIn):
    title: str = Field(..., min_length=1, max_length=100)
    summary: str = Field(..., min_length=1, max_length=200)
    content: str = Field(..., min_length=1)
    type: NotificationType
    send_mode: NotificationSendMode = NotificationSendMode.IMMEDIATE
    status: NotificationTaskStatus = NotificationTaskStatus.DRAFT
    publish_at: datetime | None = None
    repeat_type: NotificationRepeatType | None = None
    repeat_time: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    repeat_weekday: int | None = Field(default=None, ge=0, le=6)
    repeat_month_day: int | None = Field(default=None, ge=1, le=31)
    start_at: datetime | None = None
    end_at: datetime | None = None
    max_runs: int | None = Field(default=None, ge=1)

    @field_validator("title", "summary", "content")
    @classmethod
    def strip_text(cls, value: str) -> str:
        return value.strip()

    @model_validator(mode="after")
    def validate_repeat_end_condition(self) -> "SystemNotificationTaskCreateIn":
        if self.send_mode == NotificationSendMode.REPEAT and self.end_at is None and self.max_runs is None:
            raise ValueError("周期重复必须填写结束时间或最大发送次数")
        return self


class SystemNotificationTaskUpdateIn(SystemNotificationTaskCreateIn):
    id: int = Field(..., ge=1)


class SystemNotificationTaskActionIn(BaseModel):
    id: int = Field(..., ge=1)


class SystemNotificationEstimateIn(NotificationTargetIn):
    pass


class SystemNotificationLatestOut(BaseModel):
    id: int
    title: str
    summary: str
    type: str
    publish_at: datetime | None = None


class SystemNotificationUnreadOut(BaseModel):
    count: int = 0
    latest: SystemNotificationLatestOut | None = None


class SystemNotificationListItemOut(BaseModel):
    id: int
    title: str
    summary: str
    type: str
    publish_at: datetime | None = None
    read_at: datetime | None = None
    is_read: bool = False


class SystemNotificationDetailOut(SystemNotificationListItemOut):
    content: str


class SystemNotificationTaskOut(BaseModel):
    id: int
    title: str
    summary: str
    type: str
    status: str
    send_mode: str
    target_mode: str
    target_user_ids: list[int] | None = None
    target_filters: dict[str, Any] | None = None
    publish_at: datetime | None = None
    repeat_type: str | None = None
    repeat_time: str | None = None
    repeat_weekday: int | None = None
    repeat_month_day: int | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    max_runs: int | None = None
    run_count: int = 0
    next_run_at: datetime | None = None
    last_run_at: datetime | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


AllowedTaskStatusForUpdate = Literal["draft", "scheduled", "paused"]
