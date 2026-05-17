from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.core.ctx import CTX_USER_ID
from app.core.time_utils import now_local_naive
from app.models import AppUser, Moment, MomentMedia
from app.schemas.moments import MomentReviewIn
from app.schemas.base import Fail, Success, SuccessExtra
from app.utils.media_url import to_relative_media_url

router = APIRouter()


def _moment_missing() -> Fail:
    return Fail(code=400, msg="动态不存在，请刷新后重试")


def _effective_recommended(moment: Moment, user: AppUser | None) -> bool:
    if moment.recommend_override is not None:
        return bool(moment.recommend_override)
    return bool(user.is_recommended) if user else False


def _recommend_status_label(moment: Moment, user: AppUser | None) -> str:
    if moment.recommend_override is True:
        return "单条推荐"
    if moment.recommend_override is False:
        return "单条取消推荐"
    if user and user.is_recommended:
        return "推荐认证用户默认推荐"
    return "未推荐"


def _review_status_label(status: str | None) -> str:
    value = (status or "").strip().lower()
    if value == "pending":
        return "待审核"
    if value == "approved":
        return "已通过"
    if value == "rejected":
        return "已驳回"
    return value or "-"


def _apply_recommend_status_filter(q: Q, recommend_status: str, recommended_user_ids: list[int]) -> Q:
    if recommend_status == "recommended":
        q &= Q(recommend_override=True) | (Q(recommend_override__isnull=True) & Q(user_id__in=recommended_user_ids))
    elif recommend_status == "not_recommended":
        q &= Q(recommend_override=False) | (Q(recommend_override__isnull=True) & ~Q(user_id__in=recommended_user_ids))
    elif recommend_status == "override_recommended":
        q &= Q(recommend_override=True)
    elif recommend_status == "override_cancelled":
        q &= Q(recommend_override=False)
    elif recommend_status == "default":
        q &= Q(recommend_override__isnull=True)
    return q


async def _serialize_moment(
    moment: Moment,
    users: dict[int, AppUser],
    media_by_moment: dict[int, list[MomentMedia]],
) -> dict:
    user = users.get(int(moment.user_id))
    media_list = media_by_moment.get(int(moment.id), [])
    author_is_recommended = bool(user.is_recommended) if user else False
    return {
        "id": moment.id,
        "user_id": moment.user_id,
        "nickname": user.nickname if user else "",
        "phone": user.phone if user else "",
        "avatar": to_relative_media_url(user.avatar) if user else "",
        "author_is_certified_user": bool(user.is_certified_user) if user else False,
        "author_is_recommended": author_is_recommended,
        "content": moment.content or "",
        "is_pinned": bool(moment.is_pinned),
        "pinned_at": moment.pinned_at.isoformat() if moment.pinned_at else None,
        "recommend_override": moment.recommend_override,
        "review_status": moment.review_status or "approved",
        "review_status_label": _review_status_label(moment.review_status),
        "reviewed_at": moment.reviewed_at.isoformat() if moment.reviewed_at else None,
        "reviewed_by": int(moment.reviewed_by or 0) or None,
        "review_remark": moment.review_remark or "",
        "is_recommended": _effective_recommended(moment, user),
        "recommend_status_label": _recommend_status_label(moment, user),
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
    recommend_status: str = Query("all", description="推荐状态"),
    pin_status: str = Query("all", description="置顶状态"),
    review_status: str = Query("all", description="审核状态 all/pending/approved/rejected"),
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

    pin_status_value = (pin_status or "all").strip().lower()
    if pin_status_value == "pinned":
        q &= Q(is_pinned=True)
    elif pin_status_value == "normal":
        q &= Q(is_pinned=False)

    recommend_status_value = (recommend_status or "all").strip().lower()
    if recommend_status_value not in {
        "all",
        "recommended",
        "not_recommended",
        "override_recommended",
        "override_cancelled",
        "default",
    }:
        recommend_status_value = "all"
    if recommend_status_value != "all":
        recommended_user_ids = await AppUser.filter(is_recommended=True).values_list("id", flat=True)
        q = _apply_recommend_status_filter(q, recommend_status_value, list(recommended_user_ids))

    review_status_value = (review_status or "all").strip().lower()
    if review_status_value in {"pending", "approved", "rejected"}:
        q &= Q(review_status=review_status_value)

    total = await Moment.filter(q).count()
    moments = (
        await Moment.filter(q)
        .order_by("-is_pinned", "-pinned_at", "-created_at", "-id")
        .offset((page - 1) * page_size)
        .limit(page_size)
        .all()
    )
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


@router.post("/review", summary="审核用户动态")
async def review_moment(req_in: MomentReviewIn):
    moment = await Moment.filter(id=req_in.id).first()
    if not moment:
        return _moment_missing()

    normalized_status = (req_in.status or "").strip().lower()
    if normalized_status not in {"approved", "rejected"}:
        return Fail(code=400, msg="审核结果必须为 approved 或 rejected")

    current_status = (moment.review_status or "approved").strip().lower()
    if current_status != "pending":
        return Fail(code=400, msg="动态已完成审核")

    review_remark = (req_in.review_remark or "").strip()
    if normalized_status == "rejected" and not review_remark:
        return Fail(code=400, msg="驳回时必须填写审核备注")

    await Moment.filter(id=req_in.id).update(
        review_status=normalized_status,
        reviewed_at=now_local_naive(),
        reviewed_by=int(CTX_USER_ID.get() or 0) or None,
        review_remark=review_remark or None,
    )
    return Success(msg="审核成功")


@router.delete("/delete", summary="删除用户动态")
async def delete_moment(moment_id: int = Query(..., ge=1, alias="id", description="动态ID")):
    moment = await Moment.filter(id=moment_id).first()
    if not moment:
        return _moment_missing()
    await MomentMedia.filter(moment_id=moment_id).delete()
    await moment.delete()
    return Success(msg="删除成功")


@router.post("/pin", summary="置顶用户动态")
async def pin_moment(moment_id: int = Query(..., ge=1, alias="id", description="动态ID")):
    moment = await Moment.filter(id=moment_id).first()
    if not moment:
        return _moment_missing()
    await Moment.filter(id=moment_id).update(is_pinned=True, pinned_at=now_local_naive())
    return Success(msg="置顶成功")


@router.post("/unpin", summary="取消置顶用户动态")
async def unpin_moment(moment_id: int = Query(..., ge=1, alias="id", description="动态ID")):
    moment = await Moment.filter(id=moment_id).first()
    if not moment:
        return _moment_missing()
    await Moment.filter(id=moment_id).update(is_pinned=False, pinned_at=None)
    return Success(msg="取消置顶成功")


@router.post("/recommend", summary="推荐用户动态")
async def recommend_moment(moment_id: int = Query(..., ge=1, alias="id", description="动态ID")):
    moment = await Moment.filter(id=moment_id).first()
    if not moment:
        return _moment_missing()
    await Moment.filter(id=moment_id).update(recommend_override=True)
    return Success(msg="推荐成功")


@router.post("/unrecommend", summary="取消推荐用户动态")
async def unrecommend_moment(moment_id: int = Query(..., ge=1, alias="id", description="动态ID")):
    moment = await Moment.filter(id=moment_id).first()
    if not moment:
        return _moment_missing()
    await Moment.filter(id=moment_id).update(recommend_override=False)
    return Success(msg="取消推荐成功")


@router.post("/clear-recommend-override", summary="恢复动态默认推荐规则")
async def clear_moment_recommend_override(moment_id: int = Query(..., ge=1, alias="id", description="动态ID")):
    moment = await Moment.filter(id=moment_id).first()
    if not moment:
        return _moment_missing()
    await Moment.filter(id=moment_id).update(recommend_override=None)
    return Success(msg="恢复默认成功")
