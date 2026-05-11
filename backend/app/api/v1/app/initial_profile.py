from __future__ import annotations

from fastapi import APIRouter

from app.core.ctx import CTX_APP_USER_OBJ
from app.models import AppUser
from app.schemas.base import Fail, Success
from app.schemas.initial_profile import InitialProfileCompleteIn, InitialProfileGenderIn
from app.services.initial_profile_service import (
    build_initial_profile_options,
    load_initial_profile_pool,
    random_avatar as pick_random_avatar,
    random_nickname as pick_random_nickname,
    validate_avatar_choice,
    validate_nickname_choice,
)
from app.utils.media_url import to_relative_media_url

router = APIRouter()


@router.get("/options", summary="获取初始资料可选项")
async def get_initial_profile_options(gender: str = "male"):
    avatar_pool, nickname_pool = await load_initial_profile_pool()
    return Success(data=build_initial_profile_options(avatar_pool, nickname_pool, gender))


@router.post("/random-avatar", summary="随机获取初始资料头像")
async def random_initial_profile_avatar(req_in: InitialProfileGenderIn):
    avatar_pool, _ = await load_initial_profile_pool()
    gender = req_in.gender.value
    try:
        avatar = pick_random_avatar(avatar_pool, gender)
    except ValueError as exc:
        return Fail(code=400, msg=str(exc))
    return Success(data={"gender": gender, "avatar": avatar})


@router.post("/random-nickname", summary="随机获取初始资料昵称")
async def random_initial_profile_nickname(req_in: InitialProfileGenderIn):
    _, nickname_pool = await load_initial_profile_pool()
    gender = req_in.gender.value
    try:
        nickname = pick_random_nickname(nickname_pool, gender)
    except ValueError as exc:
        return Fail(code=400, msg=str(exc))
    return Success(data={"gender": gender, "nickname": nickname})


@router.post("/complete", summary="完成初始资料")
async def complete_initial_profile(req_in: InitialProfileCompleteIn):
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    avatar_pool, nickname_pool = await load_initial_profile_pool()
    gender = req_in.gender.value
    avatar = to_relative_media_url(req_in.avatar)
    nickname = req_in.nickname.strip()

    if not avatar_pool.get(gender):
        return Fail(code=400, msg="当前性别头像池未配置")
    if not nickname_pool.get(gender, {}).get("prefixes") or not nickname_pool.get(gender, {}).get("suffixes"):
        return Fail(code=400, msg="当前性别昵称池未配置")
    if not validate_avatar_choice(avatar_pool, gender, avatar):
        return Fail(code=400, msg="头像必须从当前性别头像池中选择")
    if not validate_nickname_choice(nickname_pool, gender, nickname):
        return Fail(code=400, msg="昵称必须从当前性别昵称池中选择")

    await AppUser.filter(id=app_user.id).update(
        gender=gender,
        avatar=avatar,
        nickname=nickname,
        initial_profile_completed=True,
    )
    refreshed = await AppUser.filter(id=app_user.id).first()
    if not refreshed:
        return Fail(code=500, msg="保存失败")

    return Success(
        data={
            "id": refreshed.id,
            "phone": refreshed.phone,
            "nickname": refreshed.nickname or "",
            "avatar": to_relative_media_url(refreshed.avatar),
            "gender": refreshed.gender or "male",
            "initial_profile_completed": bool(refreshed.initial_profile_completed),
        },
        msg="初始资料已完成",
    )
