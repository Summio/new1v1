from datetime import date, datetime
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, File, Query, Request, UploadFile
from tortoise.expressions import Q

from app.models import AppUser
from app.schemas.app_user import AppUserAdminUpdateIn
from app.schemas.base import Fail, Success, SuccessExtra
from app.settings.config import settings

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
    if not raw_value:
        return []
    if isinstance(raw_value, list):
        seen: set[str] = set()
        out: list[str] = []
        for item in raw_value:
            if not isinstance(item, str):
                continue
            v = item.strip()
            if not v or v in seen:
                continue
            seen.add(v)
            out.append(v)
        return out
    return []


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
        album = row.get("album_photos")
        row["album_count"] = len(album) if isinstance(album, list) else 0
    return SuccessExtra(data=data, total=total, page=page, page_size=page_size)


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
        v = req_in.avatar.strip()
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
    if req_in.album_photos is not None:
        update_data["album_photos"] = target_album
    if req_in.cover_url is not None:
        cover = req_in.cover_url.strip()
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
    image_url = str(request.base_url).rstrip("/") + relative_url
    return Success(data={"url": image_url})
