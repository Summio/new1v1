from typing import Optional

from fastapi import APIRouter, Query

from app.models import Anchor
from app.schemas.app_api import AnchorListOut, AnchorOut
from app.schemas.base import SuccessExtra

router = APIRouter()


@router.get("/anchor/list", summary="主播推荐列表(分页)")
async def anchor_list(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=50, description="每页数量"),
    gender: Optional[str] = Query(None, description="性别过滤: male/female"),
):
    q = Anchor.filter(is_online=True, apply_status="approved")
    if gender:
        q = q.filter(app_user__gender=gender)

    total = await q.count()
    anchors = await q.offset((page - 1) * page_size).limit(page_size).prefetch_related("app_user")

    rows = []
    for anchor in anchors:
        app_user = anchor.app_user
        rows.append({
            "id": anchor.id,
            "user_id": app_user.id,
            "nickname": app_user.nickname or app_user.phone,
            "avatar": anchor.avatar or app_user.avatar or "",
            "gender": app_user.gender or "secret",
            "intro": anchor.intro or "",
            "tags": anchor.tags or [],
            "call_price": anchor.call_price,
            "is_online": anchor.is_online,
            "diamonds": app_user.diamonds,
        })

    has_more = (page * page_size) < total
    return SuccessExtra(rows=rows, current=page, total=total, has_more=has_more)
