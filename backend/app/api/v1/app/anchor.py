import json
from typing import Any, Optional

from fastapi import APIRouter, Query

from app.core.redis import get_redis
from app.models import Anchor
from app.schemas.app_api import AnchorListOut, AnchorOut
from app.schemas.base import SuccessExtra

router = APIRouter()

ANCHOR_LIST_CACHE_KEY = "anchor:list"
ANCHOR_LIST_CACHE_TTL = 60  # 秒


@router.get("/anchor/list", summary="主播推荐列表(分页)")
async def anchor_list(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=50, description="每页数量"),
    gender: Optional[str] = Query(None, description="性别过滤: male/female"),
):
    # 查询已认证主播（不过滤 DB is_online，改用 Redis 在线状态）
    from app.websocket.presence import get_online_user_ids

    # 从 Redis 获取在线用户 ID 集合
    online_ids: set[int] = await get_online_user_ids()

    # 从 DB 查询已认证主播
    q = Anchor.filter(apply_status="approved")
    if gender:
        q = q.filter(app_user__gender=gender)

    all_anchors = await q.prefetch_related("app_user")
    total = len(all_anchors)

    # 分页
    start = (page - 1) * page_size
    page_anchors = all_anchors[start:start + page_size]

    all_rows = []
    for anchor in page_anchors:
        app_user = await anchor.app_user
        all_rows.append({
            "id": anchor.id,
            "user_id": app_user.id,
            "nickname": app_user.nickname or app_user.phone,
            "avatar": anchor.avatar or app_user.avatar or "",
            "gender": app_user.gender or "secret",
            "intro": anchor.intro or "",
            "tags": anchor.tags or [],
            "call_price": anchor.call_price,
            "is_online": app_user.id in online_ids,
        })

    has_more = total > page * page_size
    return SuccessExtra(rows=all_rows, current=page, total=total, has_more=has_more)
