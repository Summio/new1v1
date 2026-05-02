from datetime import datetime, timedelta
from pathlib import Path

from fastapi import APIRouter, Depends, File, UploadFile

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_OBJ
from app.models import AppUser
from app.schemas.app_user import AnchorApplyIn, AnchorApplyStatusOut
from app.schemas.base import Fail, Success
from app.settings.config import settings
from app.utils.media_url import to_relative_media_url
from app.utils.upload_files import (
    UploadValidationError,
    read_validated_image_upload,
    save_upload_content,
)

router = APIRouter()

ANCHOR_REAPPLY_COOLDOWN_HOURS = 24
_ALLOWED_IMAGE_SUFFIX = {".jpg", ".jpeg", ".png", ".webp"}


@router.post(
    "/anchor/apply/upload-face-photo",
    summary="上传主播申请正面照",
    dependencies=[Depends(DependAppAuth)],
)
async def upload_anchor_apply_face_photo(file: UploadFile = File(...)):
    app_user: AppUser = CTX_APP_USER_OBJ.get()
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

    relative_url = save_upload_content(
        base_dir=settings.BASE_DIR,
        relative_dir=Path("profile") / str(app_user.id) / "anchor_apply",
        suffix=suffix,
        content=content,
    )
    return Success(data={"url": relative_url})


@router.post("/anchor/apply", summary="申请成为主播", dependencies=[Depends(DependAppAuth)])
async def apply_anchor(req_in: AnchorApplyIn):
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    face_photo_url = to_relative_media_url(req_in.face_photo_url)
    if not face_photo_url:
        return Fail(code=400, msg="请先上传正面照")

    # 已为主播
    if app_user.is_anchor:
        return Fail(code=400, msg="您已经是主播")

    # 已有待审核申请
    if app_user.anchor_apply_status == "pending":
        return Fail(code=400, msg="您已有待审核的申请，请耐心等待")

    # 驳回冷却期
    if app_user.anchor_apply_status == "rejected" and app_user.anchor_reviewed_at:
        cooldown_deadline = app_user.anchor_reviewed_at + timedelta(hours=ANCHOR_REAPPLY_COOLDOWN_HOURS)
        if datetime.now() < cooldown_deadline:
            remaining_hours = int((cooldown_deadline - datetime.now()).total_seconds() / 3600) + 1
            return Fail(
                code=400,
                msg=f"距离上次驳回需等待 {ANCHOR_REAPPLY_COOLDOWN_HOURS} 小时后再申请（还剩 {remaining_hours} 小时）",
            )

    await AppUser.filter(id=app_user.id).update(
        anchor_apply_face_image=face_photo_url,
        anchor_apply_status="pending",
        anchor_apply_at=datetime.now(),
        anchor_reject_reason=None,
        anchor_reviewed_at=None,
    )
    return Success(data={"msg": "申请已提交，请等待审核"})


@router.get("/anchor/apply/status", summary="查询申请状态", dependencies=[Depends(DependAppAuth)])
async def get_apply_status():
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if app_user.is_anchor:
        status = "approved"
    else:
        status = (app_user.anchor_apply_status or "none").strip() or "none"
    if status not in {"none", "pending", "approved", "rejected"}:
        status = "none"

    return Success(
        data=AnchorApplyStatusOut(
            status=status,
            apply_at=app_user.anchor_apply_at,
            reject_reason=app_user.anchor_reject_reason,
            face_photo_url=to_relative_media_url(app_user.anchor_apply_face_image),
            anchor_id=app_user.id if status == "approved" else None,
            anchor_user_id=app_user.id if status == "approved" else None,
        ).model_dump(mode="json")
    )
