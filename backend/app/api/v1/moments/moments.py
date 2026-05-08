from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.models import AppUser, Moment, MomentMedia
from app.schemas.base import Fail, Success, SuccessExtra
from app.utils.media_url import to_relative_media_url

router = APIRouter()


async def _serialize_moment(
    moment: Moment,
    users: dict[int, AppUser],
    media_by_moment: dict[int, list[MomentMedia]],
) -> dict:
    user = users.get(int(moment.user_id))
    media_list = media_by_moment.get(int(moment.id), [])
    return {
        "id": moment.id,
        "user_id": moment.user_id,
        "nickname": user.nickname if user else "",
        "phone": user.phone if user else "",
        "avatar": to_relative_media_url(user.avatar) if user else "",
        "content": moment.content or "",
        "media_count": len(media_list),
        "media_list": [
            {
                "id": item.id,
                "url": to_relative_media_url(item.url),
                "media_type": item.media_type,
                "cover_url": to_relative_media_url(item.cover_url),
                "duration": item.duration,
                "sort_order": item.sort_order,
            }
            for item in media_list
        ],
        "created_at": moment.created_at.isoformat() if moment.created_at else None,
        "updated_at": moment.updated_at.isoformat() if moment.updated_at else None,
    }


@router.get("/list", summary="查看用户动态列表")
async def list_moment(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    user_id: str = Query("", description="用户ID"),
    keyword: str = Query("", description="关键词：昵称/手机号/动态内容"),
):
    q = Q()
    target_user_id = (user_id or "").strip()
    if target_user_id:
        if not target_user_id.isdigit() or int(target_user_id) <= 0:
            return Fail(code=400, msg="用户ID必须为正整数")
        q &= Q(user_id=int(target_user_id))

    keyword = (keyword or "").strip()
    if keyword:
        user_ids = await AppUser.filter(Q(nickname__contains=keyword) | Q(phone__contains=keyword)).values_list(
            "id", flat=True
        )
        q &= Q(content__contains=keyword) | Q(user_id__in=list(user_ids))

    total = await Moment.filter(q).count()
    moments = await Moment.filter(q).order_by("-created_at").offset((page - 1) * page_size).limit(page_size).all()
    user_ids = list({int(item.user_id) for item in moments})
    users = {}
    if user_ids:
        user_rows = await AppUser.filter(id__in=user_ids).all()
        users = {int(item.id): item for item in user_rows}
    moment_ids = [int(item.id) for item in moments]
    media_by_moment: dict[int, list[MomentMedia]] = {}
    if moment_ids:
        media_rows = await MomentMedia.filter(moment_id__in=moment_ids).order_by("sort_order").all()
        for item in media_rows:
            media_by_moment.setdefault(int(item.moment_id), []).append(item)
    data = [await _serialize_moment(moment, users, media_by_moment) for moment in moments]
    return SuccessExtra(data=data, total=total, page=page, page_size=page_size)


@router.delete("/delete", summary="删除用户动态")
async def delete_moment(moment_id: int = Query(..., ge=1, alias="id", description="动态ID")):
    moment = await Moment.filter(id=moment_id).first()
    if not moment:
        return Fail(code=404, msg="动态不存在")
    await MomentMedia.filter(moment_id=moment_id).delete()
    await moment.delete()
    return Success(msg="删除成功")
