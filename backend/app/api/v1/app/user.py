from fastapi import APIRouter, Query

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_OBJ
from app.models.app_user import AppUser
from app.schemas.base import Fail, Success

router = APIRouter()


@router.get("/user/info", summary="获取当前用户信息", dependencies=[DependAppAuth])
async def get_user_info():
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    if app_user.status == "banned":
        return Fail(code=403, msg=f"账号已被封禁，原因：{app_user.ban_reason or '未知'}")

    return Success(
        data={
            "id": app_user.id,
            "phone": app_user.phone,
            "nickname": app_user.nickname or app_user.phone,
            "avatar": app_user.avatar or "",
            "gender": app_user.gender or "secret",
            "coins": app_user.coins,
            "diamonds": app_user.diamonds,
            "frozen_diamonds": app_user.frozen_diamonds,
            "status": app_user.status or "normal",
            "ban_reason": app_user.ban_reason or "",
            "is_anchor": app_user.is_anchor,
            "created_at": app_user.created_at.isoformat() if app_user.created_at else None,
        }
    )


@router.get("/user/public", summary="按 user_id 获取公开用户资料", dependencies=[DependAppAuth])
async def get_user_public_profile(
    user_id: int = Query(..., description="目标用户ID"),
):
    app_user = await AppUser.filter(id=user_id).first()
    if not app_user:
        return Fail(code=404, msg="用户不存在")

    return Success(
        data={
            "id": app_user.id,
            "nickname": app_user.nickname or f"用户{app_user.id}",
            "avatar": app_user.avatar or "",
            "is_anchor": app_user.is_anchor,
            "status": app_user.status or "normal",
        }
    )
