from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.models import AppUser, Feedback
from app.schemas.base import Fail, Success, SuccessExtra
from app.schemas.feedback import FeedbackListItem

router = APIRouter()


@router.get("/list", summary="查看意见反馈列表")
async def list_feedback(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    user_id: int = Query(None, description="用户ID"),
    keyword: str = Query("", description="反馈内容关键词"),
):
    q = Q()
    if user_id:
        q &= Q(user_id=user_id)
    trimmed_keyword = keyword.strip()
    if trimmed_keyword:
        q &= Q(content__contains=trimmed_keyword)

    total = await Feedback.filter(q).count()
    records = (
        await Feedback.filter(q)
        .order_by("-created_at", "-id")
        .offset((page - 1) * page_size)
        .limit(page_size)
    )

    user_ids = list({int(row.user_id) for row in records})
    user_map: dict[int, dict] = {}
    if user_ids:
        users = await AppUser.filter(id__in=user_ids).values("id", "nickname", "phone")
        user_map = {int(item["id"]): item for item in users}

    items = []
    for row in records:
        user_info = user_map.get(int(row.user_id), {})
        items.append(
            FeedbackListItem(
                id=int(row.id),
                user_id=int(row.user_id),
                content=row.content or "",
                created_at=row.created_at,
                nickname=str(user_info.get("nickname") or ""),
                phone=str(user_info.get("phone") or ""),
            )
        )

    return SuccessExtra(
        data=[item.model_dump(mode="json") for item in items],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.delete("/delete", summary="删除意见反馈")
async def delete_feedback(id: int = Query(..., description="反馈ID")):
    deleted = await Feedback.filter(id=id).delete()
    if not deleted:
        return Fail(code=404, msg="意见反馈不存在")
    return Success(msg="删除成功")
