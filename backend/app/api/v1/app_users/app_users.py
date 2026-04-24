from datetime import date, datetime
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, File, Query, Request, UploadFile
from tortoise.expressions import Q

from app.models import AppUser
from app.schemas.app_user import AppUserAdminUpdateIn
from app.schemas.base import Fail, Success, SuccessExtra
from app.settings.config import settings
from app.utils.media_url import normalize_media_list, to_relative_media_url

router = APIRouter()
_ALLOWED_IMAGE_SUFFIX = {".jpg", ".jpeg", ".png", ".webp"}
_MAX_UPLOAD_BYTES = 10 * 1024 * 1024


def _json_safe(value):
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, list):
        return [_json_safe(v) for v in value]
    if isinstance(value, dict):
        return {k: _json_safe(v) for k, v in value.items()}
    return value


def _normalize_album(raw_value) -> list[str]:
    return normalize_media_list(raw_value)


@router.get("/list", summary="查看App用户列表")
async def list_app_user(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    phone: str = Query("", description="手机号"),
    nickname: str = Query("", description="昵称"),
    status: str = Query("", description="状态 normal/banned"),
    is_anchor: bool | None = Query(None, description="是否主播"),
    gender: str = Query("", description="性别 male/female/secret"),
    location_city: str = Query("", description="所在地(省-市)"),
):
    q = Q()
    if phone:
        q &= Q(phone__contains=phone)
    if nickname:
        q &= Q(nickname__contains=nickname)
    if status:
        q &= Q(status=status)
    if is_anchor is not None:
        q &= Q(is_anchor=is_anchor)
    if gender:
        q &= Q(gender=gender)
    if location_city:
        q &= Q(location_city__contains=location_city)

    total = await AppUser.filter(q).count()
    records = (
        await AppUser.filter(q)
        .order_by("-created_at")
        .offset((page - 1) * page_size)
        .limit(page_size)
    )

    data = [_json_safe(await row.to_dict(exclude_fields=["password"])) for row in records]
    for row in data:
        row["avatar"] = to_relative_media_url(row.get("avatar"))
        row["cover_url"] = to_relative_media_url(row.get("cover_url"))
        row["album_photos"] = _normalize_album(row.get("album_photos"))
        album = row.get("album_photos")
        row["album_count"] = len(album) if isinstance(album, list) else 0
    return SuccessExtra(data=data, total=total, page=page, page_size=page_size)


@router.get("/get", summary="查看App用户详情")
async def get_app_user(id: int = Query(..., ge=1, description="用户ID")):
    app_user = await AppUser.filter(id=id).first()
    if not app_user:
        return Fail(code=404, msg="用户不存在")
    data = _json_safe(await app_user.to_dict(exclude_fields=["password"]))
    data["avatar"] = to_relative_media_url(data.get("avatar"))
    data["cover_url"] = to_relative_media_url(data.get("cover_url"))
    data["album_photos"] = _normalize_album(data.get("album_photos"))
    album = data.get("album_photos")
    data["album_count"] = len(album) if isinstance(album, list) else 0
    return Success(data=data)


@router.post("/update", summary="更新App用户")
async def update_app_user(req_in: AppUserAdminUpdateIn):
    app_user = await AppUser.filter(id=req_in.id).first()
    if not app_user:
        return Fail(code=404, msg="用户不存在")

    current_album = _normalize_album(app_user.album_photos)
    target_album = current_album
    if req_in.album_photos is not None:
        target_album = _normalize_album(req_in.album_photos)
        if len(target_album) > 6:
            return Fail(code=400, msg="相册最多上传6张照片")

    update_data = {}
    if req_in.nickname is not None:
        v = req_in.nickname.strip()
        update_data["nickname"] = v or None
    if req_in.avatar is not None:
        v = to_relative_media_url(req_in.avatar)
        update_data["avatar"] = v or None
    if req_in.gender is not None:
        update_data["gender"] = str(req_in.gender.value)
    if req_in.birth_date is not None:
        if req_in.birth_date > date.today():
            return Fail(code=400, msg="出生日期不能晚于今天")
        update_data["birth_date"] = req_in.birth_date
    if req_in.height_cm is not None:
        update_data["height_cm"] = req_in.height_cm
    if req_in.weight_kg is not None:
        update_data["weight_kg"] = req_in.weight_kg
    if req_in.location_city is not None:
        v = req_in.location_city.strip()
        update_data["location_city"] = v or None
    if req_in.status is not None:
        update_data["status"] = req_in.status
    if req_in.is_anchor is not None:
        update_data["is_anchor"] = req_in.is_anchor
        if req_in.is_anchor:
            update_data["anchor_apply_status"] = "approved"
            update_data["anchor_reviewed_at"] = datetime.now()
    if req_in.anchor_intro is not None:
        v = req_in.anchor_intro.strip()
        update_data["anchor_intro"] = v or None
    if req_in.anchor_tags is not None:
        tags: list[str] = []
        for item in req_in.anchor_tags:
            if not isinstance(item, str):
                continue
            tag = item.strip()
            if tag:
                tags.append(tag)
        update_data["anchor_tags"] = tags
    if req_in.anchor_call_price is not None:
        update_data["anchor_call_price"] = req_in.anchor_call_price
    if req_in.anchor_reject_reason is not None:
        v = req_in.anchor_reject_reason.strip()
        update_data["anchor_reject_reason"] = v or None
    if req_in.anchor_apply_status is not None:
        update_data["anchor_apply_status"] = req_in.anchor_apply_status
        update_data["anchor_reviewed_at"] = datetime.now()
        if req_in.anchor_apply_status == "approved":
            update_data["is_anchor"] = True
            update_data["anchor_reject_reason"] = None
        elif req_in.anchor_apply_status in {"none", "rejected"}:
            update_data["is_anchor"] = False
        if req_in.anchor_apply_status == "pending":
            update_data["anchor_apply_at"] = datetime.now()
    if req_in.album_photos is not None:
        update_data["album_photos"] = target_album
    if req_in.cover_url is not None:
        cover = to_relative_media_url(req_in.cover_url)
        if cover and cover not in target_album:
            return Fail(code=400, msg="封面必须从相册中选择")
        update_data["cover_url"] = cover or None
    elif req_in.album_photos is not None:
        current_cover = (app_user.cover_url or "").strip()
        if current_cover and current_cover in target_album:
            update_data["cover_url"] = current_cover
        else:
            update_data["cover_url"] = target_album[0] if target_album else None

    if update_data:
        await AppUser.filter(id=req_in.id).update(**update_data)
    return Success(msg="更新成功")


@router.post("/upload-image", summary="后台上传App用户图片")
async def upload_app_user_image(request: Request, file: UploadFile = File(...)):
    if not file.filename:
        return Fail(code=400, msg="文件名无效")

    suffix = Path(file.filename).suffix.lower()
    if suffix not in _ALLOWED_IMAGE_SUFFIX:
        return Fail(code=400, msg="仅支持 jpg/jpeg/png/webp")

    content = await file.read()
    if not content:
        return Fail(code=400, msg="文件为空")
    if len(content) > _MAX_UPLOAD_BYTES:
        return Fail(code=400, msg="图片不能超过10MB")

    relative_dir = Path("profile") / "admin"
    abs_dir = Path(settings.BASE_DIR) / "uploads" / relative_dir
    abs_dir.mkdir(parents=True, exist_ok=True)

    filename = f"{uuid4().hex}{suffix}"
    abs_file = abs_dir / filename
    abs_file.write_bytes(content)

    relative_url = f"/uploads/{relative_dir.as_posix()}/{filename}"
    return Success(data={"url": relative_url})
