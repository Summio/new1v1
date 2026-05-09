from datetime import datetime
from typing import Any

from pydantic import BaseModel, Field


class RankingConfigIn(BaseModel):
    app_display_limit: int = Field(..., ge=1, le=100, description="App 榜单展示数量")


class RankingConfigOut(BaseModel):
    app_display_limit: int = 20


class RankingRefreshIn(BaseModel):
    board: str = Field(..., description="榜单 charm/wealth/invite")
    period: str = Field(..., description="周期 day/week/month")


class RankingMetaOut(BaseModel):
    board: str
    period: str
    period_start: datetime
    period_end: datetime
    score_unit: str
    computed_at: datetime | None = None
    app_display_limit: int | None = None


class AppRankingItemOut(BaseModel):
    rank: int
    user_id: int
    nickname: str
    avatar: str = ""
    score_gap_from_top: float = 0
    score_gap_text: str = ""


class AdminRankingItemOut(BaseModel):
    rank: int
    user_id: int
    nickname: str
    avatar: str = ""
    is_certified_user: bool = False
    board: str
    period: str
    score: float = 0
    score_text: str = ""
    period_start: datetime
    period_end: datetime
    computed_at: datetime | None = None
    source_summary: dict[str, Any] | None = None
