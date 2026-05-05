from datetime import datetime
from pathlib import Path

from fastapi import APIRouter, File, Query, UploadFile
from tortoise.expressions import Q

from app.controllers.gift import gift_controller
from app.core.redis import get_redis
from app.schemas.base import Fail, Success, SuccessExtra
from app.schemas.gift import GiftCreate, GiftUpdate
from app.settings.config import settings
from app.utils.media_url import to_relative_media_url
from app.utils.upload_files import (
    UploadValidationError,
    read_validated_image_upload,
    read_validated_upload_file,
    save_upload_content,
)

router = APIRouter()

_ALLOWED_IMAGE_SUFFIX = {".jpg", ".jpeg", ".png", ".webp"}
_ALLOWED_SVGA_SUFFIX = {".svga"}
_SVGA_MAX_BYTES = 15 * 1024 * 1024


async def _clear_gift_list_cache() -> None:
    try:
        redis = await get_redis()
        await redis.delete("gift:list:all")
    except Exception:  # noqa: BLE001
        pass


def _json_safe(value):
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, list):
        return [_json_safe(v) for v in value]
    if isinstance(value, dict):
        return {k: _json_safe(v) for k, v in value.items()}
    return value


@router.get("/list", summary="礼物列表")
async def list_gift(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    name: str = Query("", description="礼物名称"),
    is_active: bool | None = Query(None, description="是否上架"),
):
    q = Q()
    if name:
        q &= Q(name__contains=name)
    if is_active is not None:
        q &= Q(is_active=is_active)

    total, rows = await gift_controller.list(
        page=page,
        page_size=page_size,
        search=q,
        order=["price", "-id"],
    )
    data = []
    for row in rows:
        item = _json_safe(await row.to_dict())
        item["icon"] = to_relative_media_url(item.get("icon"))
        item["svga_url"] = to_relative_media_url(item.get("svga_url"))
        data.append(item)
    return SuccessExtra(data=data, total=total, page=page, page_size=page_size)


@router.get("/get", summary="礼物详情")
async def get_gift(id: int = Query(..., ge=1, description="礼物ID")):
    gift = await gift_controller.model.filter(id=id).first()
    if not gift:
        return Fail(code=404, msg="礼物不存在")
    data = _json_safe(await gift.to_dict())
    data["icon"] = to_relative_media_url(data.get("icon"))
    data["svga_url"] = to_relative_media_url(data.get("svga_url"))
    return Success(data=data)


@router.post("/create", summary="创建礼物")
async def create_gift(req_in: GiftCreate):
    payload = req_in.model_dump()
    payload["name"] = payload["name"].strip()
    payload["icon"] = to_relative_media_url(payload.get("icon"))
    payload["svga_url"] = to_relative_media_url(payload.get("svga_url"))
    created = await gift_controller.create(obj_in=GiftCreate(**payload))
    await _clear_gift_list_cache()
    return Success(data={"id": created.id}, msg="创建成功")


@router.post("/update", summary="更新礼物")
async def update_gift(req_in: GiftUpdate):
    gift = await gift_controller.model.filter(id=req_in.id).first()
    if not gift:
        return Fail(code=404, msg="礼物不存在")
    payload = req_in.model_dump()
    payload["name"] = payload["name"].strip()
    payload["icon"] = to_relative_media_url(payload.get("icon"))
    payload["svga_url"] = to_relative_media_url(payload.get("svga_url"))
    await gift_controller.update(id=req_in.id, obj_in=payload)
    await _clear_gift_list_cache()
    return Success(msg="更新成功")


@router.delete("/delete", summary="删除礼物")
async def delete_gift(id: int = Query(..., ge=1, description="礼物ID")):
    gift = await gift_controller.model.filter(id=id).first()
    if not gift:
        return Fail(code=404, msg="礼物不存在")
    await gift_controller.remove(id=id)
    await _clear_gift_list_cache()
    return Success(msg="删除成功")


@router.post("/upload-resource", summary="上传礼物资源")
async def upload_gift_resource(
    file: UploadFile = File(...),
    resource_type: str = Query("icon", description="资源类型: icon/svga"),
):
    kind = (resource_type or "").strip().lower()
    try:
        if kind == "icon":
            suffix, content = await read_validated_image_upload(
                file,
                allowed_suffixes=_ALLOWED_IMAGE_SUFFIX,
                invalid_suffix_message="仅支持 jpg/jpeg/png/webp",
            )
            relative_dir = Path("gift") / "icon"
        elif kind == "svga":
            suffix, content = await read_validated_upload_file(
                file,
                allowed_suffixes=_ALLOWED_SVGA_SUFFIX,
                max_bytes=_SVGA_MAX_BYTES,
                invalid_suffix_message="仅支持 .svga 文件",
                too_large_message="SVGA 文件不能超过15MB",
                empty_message="SVGA 文件为空",
            )
            relative_dir = Path("gift") / "svga"
        else:
            return Fail(code=400, msg="resource_type 仅支持 icon 或 svga")
    except UploadValidationError as exc:
        return Fail(code=exc.code, msg=exc.message)

    relative_url = save_upload_content(
        base_dir=settings.BASE_DIR,
        relative_dir=relative_dir,
        suffix=suffix,
        content=content,
    )
    return Success(data={"url": relative_url})
