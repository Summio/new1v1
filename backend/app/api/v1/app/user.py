from datetime import date
from pathlib import Path

from fastapi import APIRouter, Depends, File, UploadFile
from fastapi import Header, HTTPException, Query

from app.core.app_auth import DependAppAuth, logout_app_user
from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.models import AppUser
from app.schemas.app_user import AppUserProfileUpdateIn
from app.schemas.base import Fail, Success
from app.services.gift_income_service import decimal_to_float_2
from app.settings.config import settings
from app.utils.media_url import normalize_media_list, to_relative_media_url
from app.utils.upload_files import (
    UploadValidationError,
    read_validated_image_upload,
    save_upload_content,
)

router = APIRouter()
_ALLOWED_IMAGE_SUFFIX = {".jpg", ".jpeg", ".png", ".webp"}


def _mask_phone(phone: str | None) -> str:
    """手机号脱敏：138****1234"""
    if not phone or len(phone) < 7:
        return phone or ""
    return f"{phone[:3]}****{phone[-4:]}"


def _normalize_album(raw_value) -> list[str]:
    return normalize_media_list(raw_value)


@router.post("/user/logout", summary="登出")
async def logout(authorization: str = Header(None, alias="Authorization")):
    """退出登录，撤销当前 JWT token。"""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="无效的认证信息")
    token = authorization[7:]
    await logout_app_user(token)
    return Success(msg="登出成功")


@router.get("/user/info", summary="获取当前用户信息", dependencies=[Depends(DependAppAuth)])
async def get_user_info():
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    if app_user.status == "banned":
        return Fail(code=403, msg=f"账号已被封禁，原因：{app_user.ban_reason or '未知'}")

    return Success(
        data={
            "id": app_user.id,
            "phone": _mask_phone(app_user.phone),
            "nickname": app_user.nickname or app_user.phone,
            "avatar": to_relative_media_url(app_user.avatar),
            "gender": app_user.gender or "secret",
            "birth_date": app_user.birth_date.isoformat() if app_user.birth_date else None,
            "height_cm": app_user.height_cm,
            "weight_kg": app_user.weight_kg,
            "location_city": app_user.location_city or "",
            "album_photos": _normalize_album(app_user.album_photos),
            "cover_url": to_relative_media_url(app_user.cover_url),
            "coins": decimal_to_float_2(app_user.coins),
            "diamonds": decimal_to_float_2(app_user.diamonds),
            "frozen_diamonds": decimal_to_float_2(app_user.frozen_diamonds),
            "status": app_user.status or "normal",
            "ban_reason": app_user.ban_reason or "",
            "is_anchor": app_user.is_anchor,
            "created_at": app_user.created_at.isoformat() if app_user.created_at else None,
        }
    )


@router.post("/user/profile/update", summary="更新当前用户资料", dependencies=[Depends(DependAppAuth)])
async def update_user_profile(req_in: AppUserProfileUpdateIn):
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    if app_user.status == "banned":
        return Fail(code=403, msg=f"账号已被封禁，原因：{app_user.ban_reason or '未知'}")

    current_album = _normalize_album(app_user.album_photos)
    target_album = current_album
    if req_in.album_photos is not None:
        target_album = _normalize_album(req_in.album_photos)
        if len(target_album) > 6:
            return Fail(code=400, msg="相册最多上传6张照片")

    update_data = {}

    if req_in.nickname is not None:
        nickname = req_in.nickname.strip()
        update_data["nickname"] = nickname or None

    if req_in.avatar is not None:
        avatar = to_relative_media_url(req_in.avatar)
        update_data["avatar"] = avatar or None

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
        city = req_in.location_city.strip()
        update_data["location_city"] = city or None

    if req_in.album_photos is not None:
        update_data["album_photos"] = target_album

    if req_in.cover_url is not None:
        cover = to_relative_media_url(req_in.cover_url)
        if cover and cover not in target_album:
            return Fail(code=400, msg="封面必须从相册中选择")
        update_data["cover_url"] = cover or None
    elif req_in.album_photos is not None:
        # 相册发生变化时，自动修复无效封面
        current_cover = (app_user.cover_url or "").strip()
        if current_cover and current_cover in target_album:
            update_data["cover_url"] = current_cover
        else:
            update_data["cover_url"] = target_album[0] if target_album else None

    if update_data:
        await AppUser.filter(id=app_user.id).update(**update_data)

    refreshed = await AppUser.filter(id=app_user.id).first()
    if not refreshed:
        return Fail(code=500, msg="更新失败")

    return Success(
        msg="资料更新成功",
        data={
            "id": refreshed.id,
            "nickname": refreshed.nickname or refreshed.phone,
            "avatar": to_relative_media_url(refreshed.avatar),
            "gender": refreshed.gender or "secret",
            "birth_date": refreshed.birth_date.isoformat() if refreshed.birth_date else None,
            "height_cm": refreshed.height_cm,
            "weight_kg": refreshed.weight_kg,
            "location_city": refreshed.location_city or "",
            "album_photos": _normalize_album(refreshed.album_photos),
            "cover_url": to_relative_media_url(refreshed.cover_url),
        },
    )


@router.post("/user/upload-image", summary="上传资料图片", dependencies=[Depends(DependAppAuth)])
async def upload_user_image(file: UploadFile = File(...)):
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    try:
        suffix, content = await read_validated_image_upload(
            file,
            allowed_suffixes=_ALLOWED_IMAGE_SUFFIX,
            invalid_suffix_message="仅支持 jpg/jpeg/png/webp",
        )
    except UploadValidationError as exc:
        return Fail(code=exc.code, msg=exc.message)

    relative_dir = Path("profile") / str(app_user.id)
    relative_url = save_upload_content(
        base_dir=settings.BASE_DIR,
        relative_dir=relative_dir,
        suffix=suffix,
        content=content,
    )
    return Success(data={"url": relative_url})


@router.get("/user/public", summary="按 user_id 获取公开用户资料", dependencies=[Depends(DependAppAuth)])
async def get_user_public_profile(
    user_id: int = Query(..., description="目标用户ID"),
    scene: str = Query("", description="调用场景，可选 chat"),
):
    current_user_id = int(CTX_APP_USER_ID.get() or 0)
    if scene.strip().lower() == "chat" and current_user_id == user_id:
        return Fail(code=400, msg="不能和自己聊天")

    app_user = await AppUser.filter(id=user_id).first()
    if not app_user:
        return Fail(code=404, msg="用户不存在")

    return Success(
        data={
            "id": app_user.id,
            "nickname": app_user.nickname or f"用户{app_user.id}",
            "avatar": to_relative_media_url(app_user.avatar),
            "cover_url": to_relative_media_url(app_user.cover_url),
            "is_anchor": app_user.is_anchor,
            "anchor_id": app_user.id if app_user.is_anchor else None,
            "anchor_user_id": app_user.id if app_user.is_anchor else None,
            "status": app_user.status or "normal",
        }
    )
