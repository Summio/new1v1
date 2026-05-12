from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator

ComplaintStatus = Literal["pending", "processing", "resolved", "rejected"]
ComplaintHandleStatus = Literal["processing", "resolved", "rejected"]


class ComplaintCreateIn(BaseModel):
    target_user_id: int = Field(..., ge=1, description="被投诉用户ID")
    reason: str = Field(..., min_length=1, max_length=64, description="投诉原因")
    content: str = Field(..., min_length=1, max_length=1000, description="投诉补充说明")

    @field_validator("reason", "content", mode="before")
    @classmethod
    def strip_text(cls, value: str) -> str:
        return value.strip() if isinstance(value, str) else value


class ComplaintHandleIn(BaseModel):
    id: int = Field(..., ge=1, description="投诉ID")
    status: ComplaintHandleStatus = Field(..., description="处理状态")
    handle_remark: str = Field(default="", max_length=1000, description="处理备注")

    @field_validator("handle_remark")
    @classmethod
    def strip_remark(cls, value: str) -> str:
        return value.strip()


class ComplaintListItem(BaseModel):
    id: int
    complainant_id: int
    target_user_id: int
    reason: str
    content: str
    status: str
    handle_remark: str = ""
    handled_by: Optional[int] = None
    handled_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    complainant_nickname: str = ""
    complainant_phone: str = ""
    target_nickname: str = ""
    target_phone: str = ""
    target_complaint_count: int = 0
