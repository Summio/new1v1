from fastapi import APIRouter, Depends

from app.core.app_auth import AppAuthControl
from app.core.dependency import LimitLogin, LimitRegister
from app.models import AppUser
from app.schemas.app_user import AppLoginIn, AppRegisterIn, AppRegisterOut
from app.schemas.base import Fail, Success
from app.utils.media_url import to_relative_media_url
from app.utils.password import get_password_hash, verify_password

router = APIRouter()


@router.post("/login", summary="App登录(手机号+密码)", dependencies=[Depends(LimitLogin)])
async def app_login(req_in: AppLoginIn):
    app_user = await AppUser.filter(phone=req_in.phone).first()
    if not app_user:
        return Fail(code=401, msg="手机号未注册")

    if app_user.status == "banned":
        return Fail(code=403, msg=f"账号已被封禁，原因：{app_user.ban_reason or '未知'}")

    # 密码校验
    if not req_in.password:
        return Fail(code=400, msg="请输入密码")
    if not verify_password(req_in.password, app_user.password or ""):
        return Fail(code=401, msg="密码错误")

    # 生成 Token
    token = await AppAuthControl.create_app_token(app_user)

    return Success(
        data={
            "token": token,
            "user_id": app_user.id,
            "nickname": app_user.nickname or app_user.phone,
            "avatar": to_relative_media_url(app_user.avatar),
            "is_certified_user": app_user.is_certified_user,
            "initial_profile_completed": bool(app_user.initial_profile_completed),
        }
    )


@router.post("/register", summary="App用户注册", dependencies=[Depends(LimitRegister)])
async def app_register(req_in: AppRegisterIn):
    # 检查手机号是否已注册
    existing = await AppUser.filter(phone=req_in.phone).first()
    if existing:
        return Fail(code=400, msg="该手机号已注册")

    # 创建用户
    app_user = await AppUser.create(
        phone=req_in.phone,
        password=get_password_hash(req_in.password),
        nickname=None,
        avatar=None,
        status="normal",
        initial_profile_completed=False,
    )

    # 生成 Token
    token = await AppAuthControl.create_app_token(app_user)

    return Success(
        data=AppRegisterOut(
            user_id=app_user.id,
            token=token,
            initial_profile_completed=bool(app_user.initial_profile_completed),
        ).model_dump()
    )
