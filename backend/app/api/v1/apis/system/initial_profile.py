from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, File, Form, UploadFile

from app.schemas.base import Fail, Success
from app.schemas.initial_profile import (
    InitialProfileAvatarPoolIn,
    InitialProfileNicknameImportIn,
    InitialProfileNicknamePoolIn,
    InitialProfileUploadOut,
    InitialProfileUploadResult,
)
from app.services.initial_profile_service import (
    build_all_summary,
    build_initial_profile_options,
    load_initial_profile_pool,
    normalize_nickname_parts,
    parse_nickname_import_content,
    save_initial_profile_pool,
)
from app.settings.config import settings
from app.utils.upload_files import UploadValidationError, read_validated_image_upload, save_upload_content

router = APIRouter()
_ALLOWED_IMAGE_SUFFIX = {".jpg", ".jpeg", ".png", ".webp"}


@router.get("", summary="获取初始资料配置")
async def get_initial_profile_config():
    avatar_pool, nickname_pool = await load_initial_profile_pool()
    return Success(
        data={
            "avatar_pool": avatar_pool,
            "nickname_pool": nickname_pool,
            "summary": build_all_summary(avatar_pool, nickname_pool),
            "app_options": {
                gender: build_initial_profile_options(avatar_pool, nickname_pool, gender)
                for gender in ("male", "female")
            },
        }
    )


@router.put("/avatar", summary="更新初始资料头像池")
async def update_initial_profile_avatar_pool(config_in: InitialProfileAvatarPoolIn):
    await save_initial_profile_pool(avatar_pool={"male": config_in.male, "female": config_in.female})
    return Success(msg="头像池已更新")


@router.put("/nickname", summary="更新初始资料昵称池")
async def update_initial_profile_nickname_pool(config_in: InitialProfileNicknamePoolIn):
    await save_initial_profile_pool(
        nickname_pool={
            "male": {
                "prefixes": config_in.male.prefixes,
                "suffixes": config_in.male.suffixes,
            },
            "female": {
                "prefixes": config_in.female.prefixes,
                "suffixes": config_in.female.suffixes,
            },
        }
    )
    return Success(msg="昵称池已更新")


@router.post("/avatar/upload", summary="批量上传初始资料头像")
async def upload_initial_profile_avatar(
    gender: str = Form(..., description="性别 male/female"),
    files: list[UploadFile] = File(..., description="头像文件列表"),
):
    normalized_gender = str(gender or "").strip().lower()
    if normalized_gender not in {"male", "female"}:
        return Fail(code=400, msg="性别参数不正确")
    if not files:
        return Fail(code=400, msg="请先选择图片")

    avatar_pool, nickname_pool = await load_initial_profile_pool()
    avatar_pool.setdefault(normalized_gender, [])
    uploaded: list[InitialProfileUploadResult] = []
    failed: list[InitialProfileUploadResult] = []

    for file in files:
        filename = file.filename or "unknown"
        try:
            suffix, content = await read_validated_image_upload(
                file,
                allowed_suffixes=_ALLOWED_IMAGE_SUFFIX,
                invalid_suffix_message="仅支持 jpg/jpeg/png/webp",
            )
            relative_url = save_upload_content(
                base_dir=settings.BASE_DIR,
                relative_dir=Path("initial-profile") / "avatar" / normalized_gender,
                suffix=suffix,
                content=content,
            )
            avatar_pool[normalized_gender].append(relative_url)
            uploaded.append(InitialProfileUploadResult(filename=filename, url=relative_url))
        except UploadValidationError as exc:
            failed.append(InitialProfileUploadResult(filename=filename, reason=exc.message))

    await save_initial_profile_pool(avatar_pool=avatar_pool, nickname_pool=nickname_pool)

    return Success(
        data=InitialProfileUploadOut(uploaded=uploaded, failed=failed).model_dump(),
        msg="上传完成",
    )


@router.post("/nickname/import", summary="批量导入初始资料昵称素材")
async def import_initial_profile_nickname(config_in: InitialProfileNicknameImportIn):
    gender = str(config_in.gender.value)
    section = config_in.section
    items = parse_nickname_import_content(config_in.content)
    if not items:
        return Fail(code=400, msg="未识别到有效素材")

    avatar_pool, nickname_pool = await load_initial_profile_pool()
    group = nickname_pool.setdefault(gender, {"prefixes": [], "suffixes": []})
    group.setdefault("prefixes", [])
    group.setdefault("suffixes", [])

    existing = set(group[section])
    added = 0
    for item in items:
        if len(item) > 10:
            continue
        if item in existing:
            continue
        group[section].append(item)
        existing.add(item)
        added += 1

    await save_initial_profile_pool(avatar_pool=avatar_pool, nickname_pool=nickname_pool)
    return Success(data={"added": added, "items": normalize_nickname_parts(group[section])}, msg="导入完成")
