from typing import Optional

from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.models import AppUser
from app.schemas.base import SuccessExtra
from app.utils.media_url import to_relative_media_url

router = APIRouter()


def _normalize_anchor_tags(raw_value) -> list[str]:
    if not isinstance(raw_value, list):
        return []
    out: list[str] = []
    for item in raw_value:
        if not isinstance(item, str):
            continue
        tag = item.strip()
        if tag:
            out.append(tag)
    return out


@router.get("/anchor/list", summary="主播推荐列表(分页)")
async def anchor_list(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=50, description="每页数量"),
    gender: Optional[str] = Query(None, description="性别过滤: male/female"),
    keyword: Optional[str] = Query(None, description="搜索关键字：用户ID或昵称"),
):
    from app.websocket.presence import get_online_user_ids

    online_ids: set[int] = await get_online_user_ids()

    search_keyword = (keyword or "").strip()
    filters = {"status": "normal"}
    if not search_keyword:
        filters["is_anchor"] = True

    q = AppUser.filter(**filters)
    if gender:
        q = q.filter(gender=gender)
    if search_keyword:
        keyword_q = Q(nickname__icontains=search_keyword)
        if search_keyword.isdigit():
            keyword_q |= Q(id=int(search_keyword))
        q = q.filter(keyword_q)

    total = await q.count()
    users = (
        await q.order_by("-id")
        .offset((page - 1) * page_size)
        .limit(page_size)
    )

    rows = []
    for user in users:
        rows.append({
            "id": user.id,
            "user_id": user.id,
            "nickname": user.nickname or user.phone,
            "avatar": to_relative_media_url(user.avatar),
            "gender": user.gender or "secret",
            "intro": user.anchor_intro or "",
            "tags": _normalize_anchor_tags(user.anchor_tags),
            "call_price": int(user.anchor_call_price or 0),
            "is_online": user.id in online_ids,
            "is_anchor": bool(user.is_anchor),
        })

    has_more = total > page * page_size
    return SuccessExtra(rows=rows, current=page, total=total, has_more=has_more)
