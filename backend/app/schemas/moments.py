from typing import List, Optional

from pydantic import BaseModel, Field


class MomentCreateIn(BaseModel):
    """发布动态请求"""

    content: Optional[str] = Field(None, max_length=500, description="文本内容，500字以内")
    media_ids: Optional[List[int]] = Field(default_factory=list, description="已上传媒体ID列表")


class MomentMediaOut(BaseModel):
    """动态媒体输出"""

    id: int
    url: str
    media_type: int  # 1=图片, 2=视频
    sort_order: int = 0
    cover_url: Optional[str] = None
    duration: Optional[int] = None


class MomentOut(BaseModel):
    """动态输出"""

    id: int
    user_id: int
    content: Optional[str] = None
    created_at: Optional[str] = None
    media_list: List[MomentMediaOut] = Field(default_factory=list)
    user: Optional[dict] = None  # 用户信息


class MomentListOut(BaseModel):
    """动态列表响应"""

    rows: List[MomentOut] = Field(default_factory=list)
    total: int = 0
    has_more: bool = False
