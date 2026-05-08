from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile
from tortoise.expressions import Q

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_OBJ
from app.models import AppUser, Moment, MomentMedia, UserFollow
from app.schemas.base import Fail, Success, SuccessExtra
from app.schemas.moments import MomentCreateIn
from app.settings.config import settings
from app.utils.media_url import to_relative_media_url
from app.utils.upload_files import (
    MOMENT_IMAGE_MAX_BYTES,
    UploadValidationError,
    read_validated_image_upload,
    read_validated_video_upload,
    save_upload_content,
)

router = APIRouter()

_ALLOWED_IMAGE_SUFFIX = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
_ALLOWED_VIDEO_SUFFIX = {".mp4", ".mov"}
_MOMENT_FEED_CATEGORIES = {"recommend", "latest", "following"}


async def _prefetch_moment_media(moments: list[Moment]) -> dict[int, list[MomentMedia]]:
    moment_ids = [int(moment.id) for moment in moments]
    if not moment_ids:
        return {}
    rows = await MomentMedia.filter(moment_id__in=moment_ids).order_by("sort_order").all()
    media_by_moment: dict[int, list[MomentMedia]] = {}
    for row in rows:
        media_by_moment.setdefault(int(row.moment_id), []).append(row)
    return media_by_moment


async def _prefetch_moment_users(moments: list[Moment]) -> dict[int, AppUser]:
    user_ids = list({int(moment.user_id) for moment in moments})
    if not user_ids:
        return {}
    users = await AppUser.filter(id__in=user_ids).all()
    return {int(user.id): user for user in users}


async def _serialize_moment(
    moment: Moment,
    user: AppUser | None = None,
    users: dict[int, AppUser] | None = None,
    media_by_moment: dict[int, list[MomentMedia]] | None = None,
) -> dict:
    media_list = (media_by_moment or {}).get(int(moment.id), [])
    resolved_user = user or (users or {}).get(int(moment.user_id))
    recommend_override = moment.recommend_override
    author_is_recommended = bool(resolved_user.is_recommended) if resolved_user else False
    is_recommended = bool(recommend_override) if recommend_override is not None else author_is_recommended

    return {
        "id": moment.id,
        "user_id": moment.user_id,
        "content": moment.content or "",
        "created_at": moment.created_at.isoformat() if moment.created_at else None,
        "is_pinned": bool(moment.is_pinned),
        "pinned_at": moment.pinned_at.isoformat() if moment.pinned_at else None,
        "is_recommended": is_recommended,
        "recommend_override": recommend_override,
        "author_is_certified_user": bool(resolved_user.is_certified_user) if resolved_user else False,
        "author_is_recommended": author_is_recommended,
        "media_list": [
            {
                "id": m.id,
                "url": to_relative_media_url(m.url),
                "media_type": m.media_type,
                "sort_order": m.sort_order,
                "cover_url": to_relative_media_url(m.cover_url) if m.cover_url else None,
                "duration": m.duration,
            }
            for m in media_list
        ],
        "user": {
            "id": resolved_user.id if resolved_user else moment.user_id,
            "nickname": (
                (resolved_user.nickname or f"用户{resolved_user.id}") if resolved_user else f"用户{moment.user_id}"
            ),
            "avatar": to_relative_media_url(resolved_user.avatar) if resolved_user else "",
        },
    }


@router.post("/moment/upload", summary="上传动态媒体", dependencies=[Depends(DependAppAuth)])
async def upload_moment_media(
    file: UploadFile = File(...),
    media_type: int = Form(..., description="1=图片, 2=视频"),
    cover_file: UploadFile | None = File(default=None, description="视频封面图（视频必传）"),
    duration: int | None = Form(default=None, description="视频时长（秒）"),
):
    """上传动态媒体（图片或视频），返回媒体URL和信息。"""
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    if not file.filename:
        return Fail(code=400, msg="文件名无效")

    if media_type == 1:
        try:
            suffix, content = await read_validated_image_upload(
                file,
                allowed_suffixes=_ALLOWED_IMAGE_SUFFIX,
                invalid_suffix_message="仅支持 jpg/jpeg/png/gif/webp",
                max_bytes=MOMENT_IMAGE_MAX_BYTES,
                too_large_message="图片不能超过1MB",
            )
        except UploadValidationError as exc:
            return Fail(code=exc.code, msg=exc.message)
    elif media_type == 2:
        if cover_file is None or not cover_file.filename:
            return Fail(code=400, msg="视频必须选择封面")
        try:
            suffix, content = await read_validated_video_upload(
                file,
                allowed_suffixes=_ALLOWED_VIDEO_SUFFIX,
                invalid_suffix_message="仅支持 mp4/mov",
            )
        except UploadValidationError as exc:
            return Fail(code=exc.code, msg=exc.message)
    else:
        return Fail(code=400, msg="media_type 必须为 1(图片) 或 2(视频)")

    relative_dir = Path("moments") / str(app_user.id)
    relative_url = save_upload_content(
        base_dir=settings.BASE_DIR,
        relative_dir=relative_dir,
        suffix=suffix,
        content=content,
    )

    cover_url: str | None = None
    duration_value: int | None = duration if duration is not None and duration > 0 else None

    if media_type == 2 and cover_file is not None:
        try:
            cover_suffix, cover_content = await read_validated_image_upload(
                cover_file,
                allowed_suffixes=_ALLOWED_IMAGE_SUFFIX,
                invalid_suffix_message="封面仅支持 jpg/jpeg/png/gif/webp",
                max_bytes=MOMENT_IMAGE_MAX_BYTES,
                too_large_message="图片不能超过1MB",
            )
        except UploadValidationError as exc:
            if exc.message == "图片不能超过1MB":
                return Fail(code=exc.code, msg="封面不能超过1MB")
            if exc.message == "文件为空":
                return Fail(code=exc.code, msg="封面文件为空")
            return Fail(code=exc.code, msg=exc.message)
        cover_url = save_upload_content(
            base_dir=settings.BASE_DIR,
            relative_dir=relative_dir,
            suffix=cover_suffix,
            content=cover_content,
        )

    # 创建媒体记录（moment_id 暂时为空，发布动态时再绑定）
    media_record = await MomentMedia.create(
        url=relative_url,
        media_type=media_type,
        cover_url=cover_url,
        duration=duration_value,
    )
    return Success(
        data={
            "id": media_record.id,
            "url": relative_url,
            "media_type": media_type,
            "cover_url": cover_url,
            "duration": duration_value,
        }
    )


@router.post("/moment/create", summary="发布动态", dependencies=[Depends(DependAppAuth)])
async def create_moment(req_in: MomentCreateIn):
    """发布新动态，文本+已上传的媒体。"""
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    content = (req_in.content or "").strip()
    if not content and not req_in.media_ids:
        return Fail(code=400, msg="动态内容不能为空")

    if len(content) > 500:
        return Fail(code=400, msg="动态内容不能超过500字")

    media_ids = req_in.media_ids or []

    # 校验媒体数量：图片最多4张，视频最多1个（二选一）
    if media_ids:
        media_items = await MomentMedia.filter(id__in=media_ids).all()
        if len(media_items) != len(media_ids):
            return Fail(code=400, msg="部分媒体ID无效")

        image_count = sum(1 for m in media_items if m.media_type == 1)
        video_count = sum(1 for m in media_items if m.media_type == 2)
        if image_count > 4:
            return Fail(code=400, msg="图片最多4张")
        if video_count > 1:
            return Fail(code=400, msg="视频最多1个")
        if image_count > 0 and video_count > 0:
            return Fail(code=400, msg="图片和视频不能同时上传")

    # 创建动态
    moment = await Moment.create(user_id=app_user.id, content=content or None)

    # 绑定媒体到动态
    if media_ids:
        for i, media_id in enumerate(media_ids):
            await MomentMedia.filter(id=media_id).update(moment_id=moment.id, sort_order=i)

    # 重新获取完整数据
    moment = await Moment.filter(id=moment.id).first()
    media_list = await MomentMedia.filter(moment_id=moment.id).order_by("sort_order").all()

    return Success(
        data={
            "id": moment.id,
            "user_id": moment.user_id,
            "content": moment.content or "",
            "created_at": moment.created_at.isoformat() if moment.created_at else None,
            "media_list": [
                {
                    "id": m.id,
                    "url": to_relative_media_url(m.url),
                    "media_type": m.media_type,
                    "sort_order": m.sort_order,
                    "cover_url": to_relative_media_url(m.cover_url) if m.cover_url else None,
                    "duration": m.duration,
                }
                for m in media_list
            ],
            "user": {
                "id": app_user.id,
                "nickname": app_user.nickname or app_user.phone,
                "avatar": to_relative_media_url(app_user.avatar),
            },
        }
    )


@router.get("/moment/feed", summary="全局动态列表", dependencies=[Depends(DependAppAuth)])
async def get_moment_feed(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=50, description="每页数量"),
    category: str = Query("recommend", description="动态分类: recommend/latest/following"),
):
    """获取动态列表，支持推荐/最新/关注分类。"""
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    category_value = (category or "recommend").strip().lower()
    if category_value not in _MOMENT_FEED_CATEGORIES:
        category_value = "recommend"

    offset = (page - 1) * page_size

    q = Q()

    if category_value == "following":
        following_ids = await UserFollow.filter(follower_id=app_user.id).values_list("following_id", flat=True)
        q &= Q(user_id__in=list(following_ids))
    elif category_value == "recommend":
        recommended_user_ids = await AppUser.filter(is_recommended=True).values_list("id", flat=True)
        q &= Q(recommend_override=True) | (
            Q(recommend_override__isnull=True) & Q(user_id__in=list(recommended_user_ids))
        )

    total = await Moment.filter(q).count()
    moments = (
        await Moment.filter(q)
        .order_by("-is_pinned", "-pinned_at", "-created_at", "-id")
        .offset(offset)
        .limit(page_size)
        .all()
    )
    users = await _prefetch_moment_users(moments)
    media_by_moment = await _prefetch_moment_media(moments)

    rows = []
    for moment in moments:
        rows.append(await _serialize_moment(moment, users=users, media_by_moment=media_by_moment))

    return SuccessExtra(
        rows=rows,
        total=total,
        has_more=(offset + len(moments)) < total,
    )


@router.get("/moment/user", summary="指定用户动态列表", dependencies=[Depends(DependAppAuth)])
async def get_user_moments(
    user_id: int = Query(..., ge=1, description="目标用户ID"),
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(3, ge=1, le=20, description="每页数量"),
):
    """获取指定用户的动态列表，供个人详情页展示。"""
    offset = (page - 1) * page_size
    user = await AppUser.filter(id=user_id).first()
    if not user:
        return Fail(code=404, msg="用户不存在")

    total = await Moment.filter(user_id=user_id).count()
    moments = await Moment.filter(user_id=user_id).order_by("-created_at").offset(offset).limit(page_size).all()
    media_by_moment = await _prefetch_moment_media(moments)
    rows = [await _serialize_moment(moment, user=user, media_by_moment=media_by_moment) for moment in moments]

    return SuccessExtra(
        rows=rows,
        total=total,
        has_more=(offset + len(moments)) < total,
    )


@router.get("/moment/mine", summary="我的动态列表", dependencies=[Depends(DependAppAuth)])
async def get_my_moments(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=50, description="每页数量"),
):
    """获取当前用户的动态列表。"""
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    offset = (page - 1) * page_size
    total = await Moment.filter(user_id=app_user.id).count()
    moments = await Moment.filter(user_id=app_user.id).order_by("-created_at").offset(offset).limit(page_size).all()
    media_by_moment = await _prefetch_moment_media(moments)

    rows = []
    for moment in moments:
        rows.append(await _serialize_moment(moment, user=app_user, media_by_moment=media_by_moment))

    return SuccessExtra(
        rows=rows,
        total=total,
        has_more=(offset + len(moments)) < total,
    )


@router.delete("/moment/{moment_id}", summary="删除动态", dependencies=[Depends(DependAppAuth)])
async def delete_moment(moment_id: int):
    """删除自己的动态。"""
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    moment = await Moment.filter(id=moment_id).first()
    if not moment:
        return Fail(code=404, msg="动态不存在")

    if moment.user_id != app_user.id:
        return Fail(code=403, msg="无权删除他人动态")

    await MomentMedia.filter(moment_id=moment_id).delete()
    await moment.delete()

    return Success(msg="删除成功")
