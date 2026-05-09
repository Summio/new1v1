from datetime import date
from pathlib import Path

from fastapi import APIRouter, Depends, File, Header, HTTPException, Query, UploadFile
from tortoise.expressions import Q

from app.core.app_auth import DependAppAuth, logout_app_user
from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.models import AppUser, UserFollow
from app.schemas.app_user import (
    AppUserProfileUpdateIn,
    UserFollowActionOut,
    UserFollowIn,
    UserFollowStatusOut,
)
from app.schemas.base import Fail, Success, SuccessExtra
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


def _normalize_certified_tags(raw_value) -> list[str]:
    if not isinstance(raw_value, list):
        return []
    out: list[str] = []
    for item in raw_value:
        if not isinstance(item, str):
            continue
        tag = item.strip()
        if tag:
            out.append(tag)
    return out


async def _is_following(current_user_id: int, target_user_id: int) -> bool:
    if current_user_id <= 0 or target_user_id <= 0 or current_user_id == target_user_id:
        return False
    return await UserFollow.filter(
        follower_id=current_user_id,
        following_id=target_user_id,
    ).exists()


async def _serialize_user_home(app_user: AppUser, *, is_following: bool, is_online: bool) -> dict:
    return {
        "id": app_user.id,
        "user_id": app_user.id,
        "avatar": to_relative_media_url(app_user.avatar),
        "cover_url": to_relative_media_url(app_user.cover_url),
        "album_photos": _normalize_album(app_user.album_photos),
        "nickname": app_user.nickname or f"用户{app_user.id}",
        "username": app_user.nickname or f"用户{app_user.id}",
        "gender": app_user.gender or "male",
        "birth_date": app_user.birth_date.isoformat() if app_user.birth_date else None,
        "height_cm": app_user.height_cm,
        "weight_kg": app_user.weight_kg,
        "location_city": app_user.location_city or "",
        "signature": app_user.signature or "",
        "certified_intro": app_user.certified_intro or "",
        "intro": app_user.certified_intro or "",
        "tags": _normalize_certified_tags(app_user.certified_tags),
        "call_price": int(app_user.certified_call_price or 0),
        "is_online": is_online,
        "last_active": app_user.last_login.isoformat() if app_user.last_login else None,
        "status": app_user.status or "normal",
        "is_certified_user": bool(app_user.is_certified_user),
        "certification_status": app_user.certification_status or "none",
        "diamonds": int(app_user.diamonds or 0),
        "is_following": is_following,
    }


def _build_follow_keyword_query(keyword: str) -> Q:
    trimmed = keyword.strip()
    q = Q(nickname__contains=trimmed)
    if trimmed.isdigit():
        q |= Q(id=int(trimmed))
    return q


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
            "signature": app_user.signature or "",
            "gender": app_user.gender or "male",
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
            "is_certified_user": app_user.is_certified_user,
            "certification_status": app_user.certification_status or "none",
            "certified_call_price": int(app_user.certified_call_price or 0),
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

    if req_in.signature is not None:
        signature = req_in.signature.strip()
        update_data["signature"] = signature or None

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
        current_cover = to_relative_media_url(app_user.cover_url)
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
            "signature": refreshed.signature or "",
            "gender": refreshed.gender or "male",
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

    from app.websocket.presence import is_online as _is_online_user

    is_following = await _is_following(current_user_id, int(app_user.id))
    is_online = await _is_online_user(int(app_user.id))

    return Success(
        data=await _serialize_user_home(
            app_user,
            is_following=is_following,
            is_online=is_online,
        )
    )


@router.get("/user/follow/status", summary="查询关注状态", dependencies=[Depends(DependAppAuth)])
async def get_user_follow_status(
    user_id: int = Query(..., description="目标用户ID"),
):
    current_user_id = int(CTX_APP_USER_ID.get() or 0)
    if current_user_id <= 0:
        return Fail(code=401, msg="用户不存在")

    target_user = await AppUser.filter(id=user_id).first()
    if not target_user:
        return Fail(code=404, msg="用户不存在")

    is_following = await _is_following(current_user_id, target_user.id)
    return Success(
        data=UserFollowStatusOut(
            target_user_id=target_user.id,
            is_following=is_following,
        ).model_dump()
    )


@router.post("/user/follow", summary="关注用户", dependencies=[Depends(DependAppAuth)])
async def follow_user(req_in: UserFollowIn):
    current_user_id = int(CTX_APP_USER_ID.get() or 0)
    if current_user_id <= 0:
        return Fail(code=401, msg="用户不存在")
    if current_user_id == req_in.target_user_id:
        return Fail(code=400, msg="不能关注自己")

    target_user = await AppUser.filter(id=req_in.target_user_id).first()
    if not target_user:
        return Fail(code=404, msg="用户不存在")

    relation = await UserFollow.filter(
        follower_id=current_user_id,
        following_id=target_user.id,
    ).first()
    if not relation:
        await UserFollow.create(
            follower_id=current_user_id,
            following_id=target_user.id,
        )

    return Success(
        data=UserFollowActionOut(
            target_user_id=target_user.id,
            is_following=True,
        ).model_dump()
    )


@router.delete("/user/follow", summary="取消关注用户", dependencies=[Depends(DependAppAuth)])
async def unfollow_user(
    user_id: int = Query(..., description="目标用户ID"),
):
    current_user_id = int(CTX_APP_USER_ID.get() or 0)
    if current_user_id <= 0:
        return Fail(code=401, msg="用户不存在")
    if current_user_id == user_id:
        return Fail(code=400, msg="不能取消关注自己")

    relation = await UserFollow.filter(
        follower_id=current_user_id,
        following_id=user_id,
    ).first()
    if relation:
        await relation.delete()

    return Success(
        data=UserFollowActionOut(
            target_user_id=user_id,
            is_following=False,
        ).model_dump()
    )


@router.get("/user/follow/list", summary="我的关注列表", dependencies=[Depends(DependAppAuth)])
async def list_user_following(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=50, description="每页数量"),
    keyword: str = Query("", description="昵称或用户ID"),
):
    current_user_id = int(CTX_APP_USER_ID.get() or 0)
    if current_user_id <= 0:
        return Fail(code=401, msg="用户不存在")

    relation_q = UserFollow.filter(follower_id=current_user_id)
    trimmed_keyword = keyword.strip()
    if trimmed_keyword:
        matched_ids = await AppUser.filter(_build_follow_keyword_query(trimmed_keyword)).values_list("id", flat=True)
        if not matched_ids:
            return SuccessExtra(
                data=None,
                rows=[],
                current=page,
                total=0,
                has_more=False,
            )
        relation_q &= Q(following_id__in=list(matched_ids))

    total = await relation_q.count()
    relations = await relation_q.order_by("-created_at", "-id").offset((page - 1) * page_size).limit(page_size)
    following_ids = [relation.following_id for relation in relations]
    if not following_ids:
        return SuccessExtra(
            data=None,
            rows=[],
            current=page,
            total=total,
            has_more=False,
        )

    users = await AppUser.filter(id__in=following_ids).all()
    user_map = {int(user.id): user for user in users}
    from app.websocket.presence import is_online as _is_online_user

    rows: list[dict] = []
    for relation in relations:
        app_user = user_map.get(int(relation.following_id))
        if not app_user:
            continue
        rows.append(
            {
                **await _serialize_user_home(
                    app_user,
                    is_following=True,
                    is_online=await _is_online_user(int(app_user.id)),
                ),
                "followed_at": relation.created_at.isoformat() if relation.created_at else None,
            }
        )

    return SuccessExtra(
        data=None,
        rows=rows,
        current=page,
        total=total,
        has_more=page * page_size < total,
    )


@router.get("/user/fans/list", summary="我的粉丝列表", dependencies=[Depends(DependAppAuth)])
async def list_user_fans(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=50, description="每页数量"),
    keyword: str = Query("", description="昵称或用户ID"),
):
    current_user_id = int(CTX_APP_USER_ID.get() or 0)
    if current_user_id <= 0:
        return Fail(code=401, msg="用户不存在")

    relation_q = UserFollow.filter(following_id=current_user_id)
    trimmed_keyword = keyword.strip()
    if trimmed_keyword:
        matched_ids = await AppUser.filter(_build_follow_keyword_query(trimmed_keyword)).values_list("id", flat=True)
        if not matched_ids:
            return SuccessExtra(
                data=None,
                rows=[],
                current=page,
                total=0,
                has_more=False,
            )
        relation_q &= Q(follower_id__in=list(matched_ids))

    total = await relation_q.count()
    relations = await relation_q.order_by("-created_at", "-id").offset((page - 1) * page_size).limit(page_size)
    fan_ids = [relation.follower_id for relation in relations]
    if not fan_ids:
        return SuccessExtra(
            data=None,
            rows=[],
            current=page,
            total=total,
            has_more=False,
        )

    users = await AppUser.filter(id__in=fan_ids).all()
    user_map = {int(user.id): user for user in users}
    from app.websocket.presence import is_online as _is_online_user

    rows: list[dict] = []
    for relation in relations:
        app_user = user_map.get(int(relation.follower_id))
        if not app_user:
            continue
        rows.append(
            {
                **await _serialize_user_home(
                    app_user,
                    is_following=await _is_following(current_user_id, int(app_user.id)),
                    is_online=await _is_online_user(int(app_user.id)),
                ),
                "followed_at": relation.created_at.isoformat() if relation.created_at else None,
            }
        )

    return SuccessExtra(
        data=None,
        rows=rows,
        current=page,
        total=total,
        has_more=page * page_size < total,
    )
