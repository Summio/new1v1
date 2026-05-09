from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class ProfileReviewItemReviewIn(BaseModel):
    id: int = Field(..., ge=1, description="资料审核申请ID")
    item_id: str = Field(..., min_length=1, description="审核项ID")
    status: Literal["approved", "rejected"] = Field(..., description="审核结果")
    review_remark: str | None = Field(default=None, max_length=500, description="审核备注")


class ProfileReviewBulkIn(BaseModel):
    id: int = Field(..., ge=1, description="资料审核申请ID")
    review_remark: str | None = Field(default=None, max_length=500, description="审核备注")


class ProfileReviewStatusOut(BaseModel):
    status: str
    apply_at: datetime | None = None
    complete_at: datetime | None = None
