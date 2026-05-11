from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class FeedbackCreateIn(BaseModel):
    content: str = Field(..., min_length=1, max_length=1000, description="意见反馈内容")


class FeedbackListItem(BaseModel):
    id: int
    user_id: int
    content: str
    created_at: Optional[datetime] = None
    nickname: str = ""
    phone: str = ""
