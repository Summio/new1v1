from datetime import datetime, timedelta
from pathlib import Path

from fastapi import APIRouter, Depends, File, UploadFile

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_OBJ
from app.models import AppUser
from app.models.app_user_common_phrase import AppUserCommonPhrase
from app.schemas.app_user import (
    CertificationApplyIn,
    CertificationStatusOut,
    CertifiedCallPriceUpdateIn,
    CommonPhraseUpdateIn,
)
from app.schemas.base import Fail, Success
from app.services.capability_limit_service import (
    certification_denial_message,
    load_capability_limit_config,
)
from app.services.certification_price_service import (
    get_certified_call_price_tiers,
    normalize_certified_call_price,
)
from app.services.common_phrase_service import (
    build_common_phrase_slots,
    validate_common_phrase_content,
    validate_common_phrase_slot,
)
from app.settings.config import settings
from app.utils.media_url import to_relative_media_url
from app.utils.upload_files import (
    UploadValidationError,
    read_validated_image_upload,
    save_upload_content,
)

router = APIRouter()

CERTIFICATION_REAPPLY_COOLDOWN_HOURS = 24
_ALLOWED_IMAGE_SUFFIX = {".jpg", ".jpeg", ".png", ".webp"}


@router.post(
    "/certification/apply/upload-face-photo",
    summary="上传真人认证正面照",
    dependencies=[Depends(DependAppAuth)],
)
async def upload_certification_face_photo(file: UploadFile = File(...)):
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    capability_limits = await load_capability_limit_config()
    denial_message = certification_denial_message(app_user, capability_limits)
    if denial_message:
        return Fail(code=403, msg=denial_message)

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
        relative_dir=Path("profile") / str(app_user.id) / "certification",
        suffix=suffix,
        content=content,
    )
    return Success(data={"url": relative_url})


@router.post("/certification/apply", summary="申请真人认证", dependencies=[Depends(DependAppAuth)])
async def apply_certification(req_in: CertificationApplyIn):
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    capability_limits = await load_capability_limit_config()
    denial_message = certification_denial_message(app_user, capability_limits)
    if denial_message:
        return Fail(code=403, msg=denial_message)

    face_photo_url = to_relative_media_url(req_in.face_photo_url)
    if not face_photo_url:
        return Fail(code=400, msg="请先上传正面照")

    if app_user.is_certified_user:
        return Fail(code=400, msg="您已经通过真人认证")

    if app_user.certification_status == "pending":
        return Fail(code=400, msg="您已有待审核的申请，请耐心等待")

    if app_user.certification_status == "rejected" and app_user.certification_reviewed_at:
        cooldown_deadline = app_user.certification_reviewed_at + timedelta(hours=CERTIFICATION_REAPPLY_COOLDOWN_HOURS)
        if datetime.now() < cooldown_deadline:
            remaining_hours = int((cooldown_deadline - datetime.now()).total_seconds() / 3600) + 1
            return Fail(
                code=400,
                msg=f"距离上次驳回需等待 {CERTIFICATION_REAPPLY_COOLDOWN_HOURS} 小时后再申请（还剩 {remaining_hours} 小时）",
            )

    await AppUser.filter(id=app_user.id).update(
        certification_face_image=face_photo_url,
        certification_status="pending",
        certification_apply_at=datetime.now(),
        certification_reject_reason=None,
        certification_reviewed_at=None,
    )
    return Success(data={"msg": "申请已提交，请等待审核"})


@router.get("/certification/apply/status", summary="查询真人认证状态", dependencies=[Depends(DependAppAuth)])
async def get_apply_status():
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if app_user.is_certified_user:
        status = "approved"
    else:
        status = (app_user.certification_status or "none").strip() or "none"
    if status not in {"none", "pending", "approved", "rejected"}:
        status = "none"

    return Success(
        data=CertificationStatusOut(
            status=status,
            apply_at=app_user.certification_apply_at,
            reject_reason=app_user.certification_reject_reason,
            face_photo_url=to_relative_media_url(app_user.certification_face_image),
            certified_user_id=app_user.id if status == "approved" else None,
        ).model_dump(mode="json")
    )


@router.get(
    "/certification/call-price/tiers", summary="获取认证用户通话价格档位", dependencies=[Depends(DependAppAuth)]
)
async def get_call_price_tiers():
    return Success(data={"tiers": await get_certified_call_price_tiers()})


@router.post("/certification/call-price", summary="更新认证用户通话价格", dependencies=[Depends(DependAppAuth)])
async def update_call_price(req_in: CertifiedCallPriceUpdateIn):
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    normalized = await normalize_certified_call_price(
        price=req_in.price,
        is_certified_user=bool(app_user.is_certified_user),
    )
    if normalized != req_in.price:
        if not app_user.is_certified_user:
            return Fail(code=400, msg="未通过真人认证只能设置免费通话")
        return Fail(code=400, msg="请选择后台配置的通话价格档位")
    await AppUser.filter(id=app_user.id).update(certified_call_price=normalized)
    return Success(data={"price": normalized})


@router.get("/certification/common-phrases", summary="获取认证用户常用语", dependencies=[Depends(DependAppAuth)])
async def get_common_phrases():
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")
    if not app_user.is_certified_user:
        return Fail(code=403, msg="仅真人认证用户可设置常用语")

    rows = await AppUserCommonPhrase.filter(user_id=app_user.id).order_by("slot_index").all()
    return Success(data={"phrases": build_common_phrase_slots(rows)})


@router.put(
    "/certification/common-phrases/{slot_index}",
    summary="提交认证用户常用语审核",
    dependencies=[Depends(DependAppAuth)],
)
async def update_common_phrase(slot_index: int, req_in: CommonPhraseUpdateIn):
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")
    if not app_user.is_certified_user:
        return Fail(code=403, msg="仅真人认证用户可设置常用语")

    try:
        normalized_slot = validate_common_phrase_slot(slot_index)
        content = validate_common_phrase_content(req_in.content)
    except ValueError as exc:
        return Fail(code=400, msg=str(exc))

    row = await AppUserCommonPhrase.filter(user_id=app_user.id, slot_index=normalized_slot).first()
    if row:
        row.pending_content = content
        row.review_status = "pending"
        row.review_remark = ""
        row.submitted_at = datetime.now()
        row.reviewed_at = None
        row.reviewed_by = None
        await row.save(
            update_fields=[
                "pending_content",
                "review_status",
                "review_remark",
                "submitted_at",
                "reviewed_at",
                "reviewed_by",
                "updated_at",
            ]
        )
    else:
        row = await AppUserCommonPhrase.create(
            user_id=app_user.id,
            slot_index=normalized_slot,
            pending_content=content,
            review_status="pending",
            review_remark="",
            submitted_at=datetime.now(),
        )
    return Success(data={"phrase": build_common_phrase_slots([row])[normalized_slot - 1]}, msg="已提交审核")
