from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Query, UploadFile, Form

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_OBJ, CTX_APP_USER_ID
from app.models import Moment, MomentMedia, AppUser
from app.schemas.base import Fail, Success, SuccessExtra
from app.schemas.moments import MomentCreateIn
from app.settings.config import settings
from app.utils.media_url import to_relative_media_url

router = APIRouter()

_ALLOWED_IMAGE_SUFFIX = {".jpg", ".jpeg", ".png", ".webp", ".gif"}
_ALLOWED_VIDEO_SUFFIX = {".mp4", ".mov"}
_MAX_IMAGE_BYTES = 10 * 1024 * 1024  # 10MB
_MAX_VIDEO_BYTES = 100 * 1024 * 1024  # 100MB


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

    suffix = Path(file.filename).suffix.lower()

    if media_type == 1:
        if suffix not in _ALLOWED_IMAGE_SUFFIX:
            return Fail(code=400, msg="仅支持 jpg/jpeg/png/gif/webp")
        max_bytes = _MAX_IMAGE_BYTES
    elif media_type == 2:
        if suffix not in _ALLOWED_VIDEO_SUFFIX:
            return Fail(code=400, msg="仅支持 mp4/mov")
        max_bytes = _MAX_VIDEO_BYTES
        if cover_file is None or not cover_file.filename:
            return Fail(code=400, msg="视频必须选择封面")
    else:
        return Fail(code=400, msg="media_type 必须为 1(图片) 或 2(视频)")

    content = await file.read()
    if not content:
        return Fail(code=400, msg="文件为空")
    if len(content) > max_bytes:
        size_mb = max_bytes // (1024 * 1024)
        return Fail(code=400, msg=f"文件不能超过 {size_mb}MB")

    relative_dir = Path("moments") / str(app_user.id)
    abs_dir = Path(settings.BASE_DIR) / "uploads" / relative_dir
    abs_dir.mkdir(parents=True, exist_ok=True)

    filename = f"{uuid4().hex}{suffix}"
    abs_file = abs_dir / filename
    abs_file.write_bytes(content)

    cover_url: str | None = None
    duration_value: int | None = duration if duration is not None and duration > 0 else None

    if media_type == 2 and cover_file is not None:
        cover_suffix = Path(cover_file.filename).suffix.lower()
        if cover_suffix not in _ALLOWED_IMAGE_SUFFIX:
            return Fail(code=400, msg="封面仅支持 jpg/jpeg/png/gif/webp")
        cover_content = await cover_file.read()
        if not cover_content:
            return Fail(code=400, msg="封面文件为空")
        if len(cover_content) > _MAX_IMAGE_BYTES:
            return Fail(code=400, msg="封面不能超过 10MB")
        cover_filename = f"{uuid4().hex}{cover_suffix}"
        cover_abs_file = abs_dir / cover_filename
        cover_abs_file.write_bytes(cover_content)
        cover_url = f"/uploads/{relative_dir.as_posix()}/{cover_filename}"

    relative_url = f"/uploads/{relative_dir.as_posix()}/{filename}"

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
):
    """获取全局动态列表，最新在上。"""
    offset = (page - 1) * page_size
    total = await Moment.all().count()
    moments = await Moment.all().order_by("-created_at").offset(offset).limit(page_size).all()

    rows = []
    for moment in moments:
        user = await AppUser.filter(id=moment.user_id).first()
        media_list = await MomentMedia.filter(moment_id=moment.id).order_by("sort_order").all()

        rows.append({
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
                "id": user.id if user else moment.user_id,
                "nickname": (user.nickname or f"用户{user.id}") if user else f"用户{moment.user_id}",
                "avatar": to_relative_media_url(user.avatar) if user else "",
            },
        })

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

    rows = []
    for moment in moments:
        media_list = await MomentMedia.filter(moment_id=moment.id).order_by("sort_order").all()

        rows.append({
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
        })

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
