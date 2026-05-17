from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, File, Query, UploadFile
from tortoise.expressions import F, Q
from tortoise.transactions import in_transaction

from app.core.china_locations import normalize_location_city
from app.core.ctx import CTX_USER_ID
from app.core.time_utils import now_local_naive
from app.core.profile_basic_fields import (
    normalize_birth_date,
    normalize_height_cm,
    normalize_weight_kg,
)
from app.models import (
    AppUser,
    AppUserCommonPhrase,
    AppUserProfileReviewApply,
    AppUserTokenAdjustRecord,
    CallRecord,
    GiftRecord,
    ImTextMessageChargeRecord,
    RechargeOrder,
    User,
    WithdrawApply,
)
from app.schemas.app_user import (
    AppUserAdminUpdateIn,
    AppUserBalanceAdjustIn,
    CertificationReviewIn,
    CommonPhraseReviewIn,
)
from app.schemas.app_user_profile_review import (
    ProfileReviewBulkIn,
    ProfileReviewItemReviewIn,
)
from app.schemas.base import Fail, Success, SuccessExtra
from app.services.balance_event_service import publish_balance_changed
from app.services.certification_price_service import normalize_certified_call_price
from app.services.common_phrase_service import apply_common_phrase_review
from app.services.gift_income_service import decimal_to_float_2
from app.services.profile_review_service import (
    ProfileReviewValidationError,
    apply_approved_profile_review_items,
    mark_all_review_items,
    review_items_have_pending,
    update_review_item_status,
)
from app.settings.config import settings
from app.utils.media_url import normalize_media_list, to_relative_media_url
from app.utils.upload_files import (
    UploadValidationError,
    read_validated_image_upload,
    save_upload_content,
)

router = APIRouter()
_ALLOWED_IMAGE_SUFFIX = {".jpg", ".jpeg", ".png", ".webp"}


def _json_safe(value):
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return decimal_to_float_2(value)
    if isinstance(value, list):
        return [_json_safe(v) for v in value]
    if isinstance(value, dict):
        return {k: _json_safe(v) for k, v in value.items()}
    return value


def _normalize_album(raw_value) -> list[str]:
    return normalize_media_list(raw_value)


def _format_bill_dt(value: datetime | None) -> str:
    if not value:
        return ""
    return value.strftime("%Y-%m-%d %H:%M:%S")


def _amount_decimal(value) -> Decimal:
    try:
        return Decimal(str(value or "0"))
    except Exception:  # noqa: BLE001
        return Decimal("0")


def _format_profile_review_apply(apply: AppUserProfileReviewApply, user: AppUser) -> dict:
    before_snapshot = apply.before_snapshot or {}
    after_snapshot = apply.after_snapshot or {}
    review_items = apply.review_items or []
    return {
        "id": apply.id,
        "user_id": int(user.id),
        "phone": user.phone or "",
        "nickname": user.nickname or user.phone or "",
        "avatar": to_relative_media_url(user.avatar),
        "status": apply.status or "pending",
        "submitted_at": apply.submitted_at.isoformat() if apply.submitted_at else None,
        "completed_at": apply.completed_at.isoformat() if apply.completed_at else None,
        "completed_by": int(apply.completed_by or 0) or None,
        "review_remark": apply.review_remark or "",
        "before_snapshot": before_snapshot,
        "after_snapshot": after_snapshot,
        "review_items": review_items,
        "review_item_count": len(review_items),
    }


def _format_common_phrase_review(row: AppUserCommonPhrase, user: AppUser | None) -> dict:
    return {
        "id": row.id,
        "user_id": int(row.user_id),
        "phone": user.phone if user else "",
        "nickname": (user.nickname or user.phone or f"用户{row.user_id}") if user else f"用户{row.user_id}",
        "avatar": to_relative_media_url(user.avatar) if user else None,
        "slot_index": int(row.slot_index or 0),
        "approved_content": row.approved_content or "",
        "pending_content": row.pending_content or "",
        "review_status": row.review_status or "none",
        "review_remark": row.review_remark or "",
        "submitted_at": row.submitted_at.isoformat() if row.submitted_at else None,
        "reviewed_at": row.reviewed_at.isoformat() if row.reviewed_at else None,
        "reviewed_by": int(row.reviewed_by or 0) or None,
    }


@router.get("/list", summary="查看App用户列表")
async def list_app_user(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    user_id: int | None = Query(None, ge=1, description="用户ID"),
    phone: str = Query("", description="手机号"),
    nickname: str = Query("", description="昵称"),
    status: str = Query("", description="状态 normal/banned"),
    is_certified_user: bool | None = Query(None, description="是否真人认证用户"),
    certification_status: str = Query("", description="真人认证状态 none/pending/approved/rejected"),
    gender: Literal["", "male", "female"] = Query("", description="性别 male/female"),
    location_city: str = Query("", description="所在地(省-市)"),
):
    q = Q()
    if user_id:
        q &= Q(id=user_id)
    if phone:
        q &= Q(phone__contains=phone)
    if nickname:
        q &= Q(nickname__contains=nickname)
    if status:
        q &= Q(status=status)
    if is_certified_user is not None:
        q &= Q(is_certified_user=is_certified_user)
    if certification_status:
        q &= Q(certification_status=certification_status)
    if gender:
        q &= Q(gender=gender)
    if location_city:
        q &= Q(location_city__contains=location_city)

    total = await AppUser.filter(q).count()
    records = await AppUser.filter(q).order_by("-created_at").offset((page - 1) * page_size).limit(page_size)

    data = [_json_safe(await row.to_dict(exclude_fields=["password"])) for row in records]
    for row in data:
        row["avatar"] = to_relative_media_url(row.get("avatar"))
        row["cover_url"] = to_relative_media_url(row.get("cover_url"))
        row["certification_face_image"] = to_relative_media_url(row.get("certification_face_image"))
        row["album_photos"] = _normalize_album(row.get("album_photos"))
        album = row.get("album_photos")
        row["album_count"] = len(album) if isinstance(album, list) else 0
    return SuccessExtra(data=data, total=total, page=page, page_size=page_size)


@router.get("/get", summary="查看App用户详情")
async def get_app_user(id: int = Query(..., ge=1, description="用户ID")):
    app_user = await AppUser.filter(id=id).first()
    if not app_user:
        return Fail(code=404, msg="用户不存在")
    data = _json_safe(await app_user.to_dict(exclude_fields=["password"]))
    data["avatar"] = to_relative_media_url(data.get("avatar"))
    data["cover_url"] = to_relative_media_url(data.get("cover_url"))
    data["certification_face_image"] = to_relative_media_url(data.get("certification_face_image"))
    data["album_photos"] = _normalize_album(data.get("album_photos"))
    album = data.get("album_photos")
    data["album_count"] = len(album) if isinstance(album, list) else 0
    return Success(data=data)


@router.post("/balance/adjust", summary="调整App用户余额")
async def adjust_app_user_balance(req_in: AppUserBalanceAdjustIn):
    reason = req_in.reason.strip()
    if not reason:
        return Fail(code=400, msg="请填写操作原因")

    operator_user_id = int(CTX_USER_ID.get() or 0)
    operator = await User.filter(id=operator_user_id).first() if operator_user_id else None
    operator_username = ""
    if operator:
        operator_username = (operator.username or operator.alias or "").strip()

    async with in_transaction() as conn:
        app_user = await AppUser.filter(id=req_in.id).using_db(conn).select_for_update().first()
        if not app_user:
            return Fail(code=404, msg="用户不存在")

        amount = Decimal(str(req_in.amount))
        before_amount = Decimal(str(getattr(app_user, req_in.asset_type) or "0"))

        if req_in.asset_type == "coins":
            if req_in.action == "increase":
                await AppUser.filter(id=req_in.id).using_db(conn).update(coins=F("coins") + req_in.amount)
            else:
                if before_amount < amount:
                    return Fail(code=501, msg="金币余额不足，无法扣除")
                await AppUser.filter(id=req_in.id).using_db(conn).update(coins=F("coins") - req_in.amount)
        else:
            if req_in.action == "increase":
                await AppUser.filter(id=req_in.id).using_db(conn).update(diamonds=F("diamonds") + req_in.amount)
            else:
                if before_amount < amount:
                    return Fail(code=501, msg="钻石余额不足，无法扣除")
                await AppUser.filter(id=req_in.id).using_db(conn).update(diamonds=F("diamonds") - req_in.amount)

        refreshed = await AppUser.filter(id=req_in.id).using_db(conn).first()
        after_amount = Decimal(str(getattr(refreshed, req_in.asset_type) if refreshed else before_amount))
        await AppUserTokenAdjustRecord.create(
            app_user_id=req_in.id,
            operator_user_id=operator_user_id,
            operator_username=operator_username,
            asset_type=req_in.asset_type,
            action=req_in.action,
            amount=amount,
            before_amount=before_amount,
            after_amount=after_amount,
            reason=reason,
            using_db=conn,
        )

    await publish_balance_changed(int(req_in.id), source="balance_adjust")

    return Success(
        data={
            "id": int(refreshed.id) if refreshed else req_in.id,
            "coins": decimal_to_float_2(refreshed.coins if refreshed else 0),
            "diamonds": decimal_to_float_2(refreshed.diamonds if refreshed else 0),
            "frozen_diamonds": decimal_to_float_2(refreshed.frozen_diamonds if refreshed else 0),
        },
        msg="调整成功",
    )


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
        v = to_relative_media_url(req_in.avatar)
        update_data["avatar"] = v or None
    if req_in.signature is not None:
        v = req_in.signature.strip()
        update_data["signature"] = v or None
    if req_in.gender is not None:
        update_data["gender"] = str(req_in.gender.value)
    if req_in.birth_date is not None:
        normalized_birth_date = normalize_birth_date(req_in.birth_date)
        if isinstance(normalized_birth_date, str):
            return Fail(code=400, msg=normalized_birth_date)
        update_data["birth_date"] = normalized_birth_date
    if req_in.height_cm is not None:
        normalized_height_cm = normalize_height_cm(req_in.height_cm)
        if isinstance(normalized_height_cm, str):
            return Fail(code=400, msg=normalized_height_cm)
        update_data["height_cm"] = normalized_height_cm
    if req_in.weight_kg is not None:
        normalized_weight_kg = normalize_weight_kg(req_in.weight_kg)
        if isinstance(normalized_weight_kg, str):
            return Fail(code=400, msg=normalized_weight_kg)
        update_data["weight_kg"] = normalized_weight_kg
    if req_in.location_city is not None:
        v = req_in.location_city.strip()
        normalized_location_city = normalize_location_city(v)
        if v and normalized_location_city is None:
            return Fail(code=400, msg="所在地不合法")
        update_data["location_city"] = normalized_location_city
    if req_in.status is not None:
        update_data["status"] = req_in.status
    if req_in.is_certified_user is not None:
        update_data["is_certified_user"] = req_in.is_certified_user
        if req_in.is_certified_user:
            update_data["certification_status"] = "approved"
            update_data["certification_reviewed_at"] = now_local_naive()
    if req_in.is_recommended is not None:
        update_data["is_recommended"] = req_in.is_recommended
    if req_in.recommend_weight is not None:
        update_data["recommend_weight"] = req_in.recommend_weight
    if req_in.certified_intro is not None:
        v = req_in.certified_intro.strip()
        update_data["certified_intro"] = v or None
    if req_in.certified_tags is not None:
        tags: list[str] = []
        for item in req_in.certified_tags:
            if not isinstance(item, str):
                continue
            tag = item.strip()
            if tag:
                tags.append(tag)
        update_data["certified_tags"] = tags
    if req_in.certified_call_price is not None:
        update_data["certified_call_price"] = req_in.certified_call_price
    if req_in.certification_reject_reason is not None:
        v = req_in.certification_reject_reason.strip()
        update_data["certification_reject_reason"] = v or None
    if req_in.certification_face_image is not None:
        v = to_relative_media_url(req_in.certification_face_image)
        update_data["certification_face_image"] = v or None
    if req_in.certification_status is not None:
        reject_reason = (req_in.certification_reject_reason or "").strip()
        target_face_image = to_relative_media_url(
            req_in.certification_face_image
            if req_in.certification_face_image is not None
            else app_user.certification_face_image
        )
        update_data["certification_status"] = req_in.certification_status
        update_data["certification_reviewed_at"] = now_local_naive()
        if req_in.certification_status == "approved":
            if not target_face_image:
                return Fail(code=400, msg="申请正面照缺失，无法通过审核")
            update_data["is_certified_user"] = True
            update_data["certification_reject_reason"] = None
        elif req_in.certification_status in {"none", "rejected"}:
            update_data["is_certified_user"] = False
        if req_in.certification_status == "rejected":
            if not reject_reason:
                return Fail(code=400, msg="驳回时必须填写驳回原因")
            update_data["certification_reject_reason"] = reject_reason
        if req_in.certification_status == "pending":
            update_data["certification_apply_at"] = now_local_naive()
            update_data["certification_reviewed_at"] = None
            update_data["certification_reject_reason"] = None
    if "is_certified_user" in update_data or "certified_call_price" in update_data:
        target_certified = bool(update_data.get("is_certified_user", app_user.is_certified_user))
        target_price = int(update_data.get("certified_call_price", app_user.certified_call_price or 0))
        normalized_price = await normalize_certified_call_price(
            price=target_price,
            is_certified_user=target_certified,
        )
        if target_certified and req_in.certified_call_price is not None and normalized_price != target_price:
            return Fail(code=400, msg="请选择后台配置的通话价格档位")
        update_data["certified_call_price"] = normalized_price
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
        await AppUser.filter(id=req_in.id).update(**update_data)
    return Success(msg="更新成功")


@router.post("/certification/review", summary="审核真人认证申请")
async def review_certification(req_in: CertificationReviewIn):
    app_user = await AppUser.filter(id=req_in.id).first()
    if not app_user:
        return Fail(code=404, msg="用户不存在")

    if req_in.status == "approved":
        if not to_relative_media_url(app_user.certification_face_image):
            return Fail(code=400, msg="认证正面照缺失，无法通过审核")
        await AppUser.filter(id=app_user.id).update(
            is_certified_user=True,
            certification_status="approved",
            certification_reject_reason=None,
            certification_reviewed_at=now_local_naive(),
            certified_call_price=await normalize_certified_call_price(
                price=int(app_user.certified_call_price or 0),
                is_certified_user=True,
            ),
        )
        return Success(msg="审核通过")

    reject_reason = (req_in.reject_reason or "").strip()
    if not reject_reason:
        return Fail(code=400, msg="驳回时必须填写驳回原因")
    await AppUser.filter(id=app_user.id).update(
        is_certified_user=False,
        certification_status="rejected",
        certification_reject_reason=reject_reason,
        certification_reviewed_at=now_local_naive(),
        certified_call_price=0,
    )
    return Success(msg="已驳回申请")


@router.post("/upload-image", summary="后台上传App用户图片")
async def upload_app_user_image(file: UploadFile = File(...)):
    try:
        suffix, content = await read_validated_image_upload(
            file,
            allowed_suffixes=_ALLOWED_IMAGE_SUFFIX,
            invalid_suffix_message="仅支持 jpg/jpeg/png/webp",
        )
    except UploadValidationError as exc:
        return Fail(code=exc.code, msg=exc.message)

    relative_dir = Path("profile") / "admin"
    relative_url = save_upload_content(
        base_dir=settings.BASE_DIR,
        relative_dir=relative_dir,
        suffix=suffix,
        content=content,
    )
    return Success(data={"url": relative_url})


@router.get("/profile-review/list", summary="查看App用户资料编辑申请列表")
async def list_profile_review_apply(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    status: str = Query("pending", description="申请状态 pending/reviewing/completed/cancelled"),
    phone: str = Query("", description="手机号"),
    nickname: str = Query("", description="昵称"),
    user_id: int | None = Query(None, ge=1, description="用户ID"),
):
    q = Q()
    normalized_status = (status or "").strip()
    if normalized_status:
        q &= Q(status=normalized_status)

    target_user_ids: list[int] | None = None
    if user_id:
        q &= Q(user_id=user_id)
    if phone or nickname:
        user_q = Q()
        if phone:
            user_q &= Q(phone__contains=phone)
        if nickname:
            user_q &= Q(nickname__contains=nickname)
        matched_user_ids = await AppUser.filter(user_q).values_list("id", flat=True)
        target_user_ids = [int(item) for item in matched_user_ids]
        if not target_user_ids:
            return SuccessExtra(data=None, rows=[], current=page, total=0, has_more=False)
        q &= Q(user_id__in=target_user_ids)

    total = await AppUserProfileReviewApply.filter(q).count()
    applies = (
        await AppUserProfileReviewApply.filter(q)
        .order_by("-submitted_at", "-id")
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    apply_user_ids = [int(item.user_id) for item in applies]
    users = await AppUser.filter(id__in=apply_user_ids).all() if apply_user_ids else []
    user_map = {int(user.id): user for user in users}
    rows = []
    for apply in applies:
        user = user_map.get(int(apply.user_id))
        if not user:
            continue
        rows.append(_format_profile_review_apply(apply, user))
    return SuccessExtra(
        data=None,
        rows=rows,
        current=page,
        total=total,
        has_more=page * page_size < total,
    )


@router.get("/profile-review/get", summary="查看App用户资料编辑申请详情")
async def get_profile_review_apply(id: int = Query(..., ge=1, description="申请ID")):
    apply = await AppUserProfileReviewApply.filter(id=id).first()
    if not apply:
        return Fail(code=404, msg="申请不存在")
    user = await AppUser.filter(id=apply.user_id).first()
    if not user:
        return Fail(code=404, msg="用户不存在")
    return Success(data=_format_profile_review_apply(apply, user))


@router.post("/profile-review/item/review", summary="审核App用户资料编辑单项")
async def review_profile_review_item(req_in: ProfileReviewItemReviewIn):
    apply = await AppUserProfileReviewApply.filter(id=req_in.id).first()
    if not apply:
        return Fail(code=404, msg="申请不存在")
    if (apply.status or "pending") == "completed":
        return Fail(code=400, msg="申请已完成，不能继续审核")

    try:
        next_items = update_review_item_status(
            apply.review_items or [],
            item_id=req_in.item_id,
            status=req_in.status,
            reviewed_by=int(CTX_USER_ID.get() or 0) or None,
            review_remark=req_in.review_remark,
        )
    except ProfileReviewValidationError as exc:
        return Fail(code=400, msg=str(exc))

    apply.review_items = next_items
    apply.status = "reviewing"
    await apply.save(update_fields=["review_items", "status", "updated_at"])
    return Success(msg="审核成功")


@router.post("/profile-review/approve-all", summary="全部通过App用户资料编辑申请")
async def approve_all_profile_review_items(req_in: ProfileReviewBulkIn):
    apply = await AppUserProfileReviewApply.filter(id=req_in.id).first()
    if not apply:
        return Fail(code=404, msg="申请不存在")
    if (apply.status or "pending") == "completed":
        return Fail(code=400, msg="申请已完成，不能继续审核")

    apply.review_items = mark_all_review_items(
        apply.review_items or [],
        status="approved",
        reviewed_by=int(CTX_USER_ID.get() or 0) or None,
    )
    apply.status = "reviewing"
    await apply.save(update_fields=["review_items", "status", "updated_at"])
    return Success(msg="已全部通过")


@router.post("/profile-review/reject-all", summary="全部驳回App用户资料编辑申请")
async def reject_all_profile_review_items(req_in: ProfileReviewBulkIn):
    apply = await AppUserProfileReviewApply.filter(id=req_in.id).first()
    if not apply:
        return Fail(code=404, msg="申请不存在")
    if (apply.status or "pending") == "completed":
        return Fail(code=400, msg="申请已完成，不能继续审核")

    apply.review_items = mark_all_review_items(
        apply.review_items or [],
        status="rejected",
        reviewed_by=int(CTX_USER_ID.get() or 0) or None,
    )
    apply.status = "reviewing"
    await apply.save(update_fields=["review_items", "status", "updated_at"])
    return Success(msg="已全部驳回")


@router.post("/profile-review/complete", summary="完成App用户资料编辑审核")
async def complete_profile_review(req_in: ProfileReviewBulkIn):
    apply = await AppUserProfileReviewApply.filter(id=req_in.id).first()
    if not apply:
        return Fail(code=404, msg="申请不存在")
    if (apply.status or "pending") == "completed":
        return Fail(code=400, msg="申请已完成")
    review_items = apply.review_items or []
    if review_items_have_pending(review_items):
        return Fail(code=400, msg="还有未审核项")

    user = await AppUser.filter(id=apply.user_id).first()
    if not user:
        return Fail(code=404, msg="用户不存在")

    try:
        update_data = apply_approved_profile_review_items(
            before_snapshot=apply.before_snapshot or {},
            after_snapshot=apply.after_snapshot or {},
            review_items=review_items,
        )
    except ProfileReviewValidationError as exc:
        return Fail(code=400, msg=str(exc))

    async with in_transaction() as conn:
        await AppUser.filter(id=user.id).using_db(conn).update(**update_data)
        await AppUserProfileReviewApply.filter(id=apply.id).using_db(conn).update(
            status="completed",
            completed_at=now_local_naive(),
            completed_by=int(CTX_USER_ID.get() or 0) or None,
            review_remark=(req_in.review_remark or "").strip() or None,
            updated_at=now_local_naive(),
        )

    return Success(msg="审核完成")


@router.get("/common-phrase-review/list", summary="查看常用语审核列表")
async def list_common_phrase_review(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    status: str = Query("pending", description="审核状态 all/none/pending/approved/rejected"),
    phone: str = Query("", description="手机号"),
    nickname: str = Query("", description="昵称"),
    user_id: int | None = Query(None, ge=1, description="用户ID"),
):
    q = Q()
    normalized_status = (status or "pending").strip()
    if normalized_status and normalized_status != "all":
        q &= Q(review_status=normalized_status)
    if user_id:
        q &= Q(user_id=user_id)
    if phone or nickname:
        user_q = Q()
        if phone:
            user_q &= Q(phone__contains=phone)
        if nickname:
            user_q &= Q(nickname__contains=nickname)
        matched_user_ids = await AppUser.filter(user_q).values_list("id", flat=True)
        matched_user_ids = [int(item) for item in matched_user_ids]
        if not matched_user_ids:
            return SuccessExtra(data=None, rows=[], current=page, total=0, has_more=False)
        q &= Q(user_id__in=matched_user_ids)

    total = await AppUserCommonPhrase.filter(q).count()
    rows = (
        await AppUserCommonPhrase.filter(q)
        .order_by("-submitted_at", "-id")
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    user_ids = [int(row.user_id) for row in rows]
    users = await AppUser.filter(id__in=user_ids).all() if user_ids else []
    user_map = {int(user.id): user for user in users}
    return SuccessExtra(
        data=None,
        rows=[_format_common_phrase_review(row, user_map.get(int(row.user_id))) for row in rows],
        current=page,
        total=total,
        has_more=page * page_size < total,
    )


@router.get("/common-phrase-review/get", summary="查看常用语审核详情")
async def get_common_phrase_review(id: int = Query(..., ge=1, description="常用语记录ID")):
    row = await AppUserCommonPhrase.filter(id=id).first()
    if not row:
        return Fail(code=404, msg="常用语不存在")
    user = await AppUser.filter(id=row.user_id).first()
    return Success(data=_format_common_phrase_review(row, user))


@router.post("/common-phrase-review/review", summary="审核常用语")
async def review_common_phrase(req_in: CommonPhraseReviewIn):
    row = await AppUserCommonPhrase.filter(id=req_in.id).first()
    if not row:
        return Fail(code=404, msg="常用语不存在")
    if (row.review_status or "none") != "pending":
        return Fail(code=400, msg="当前常用语不是待审核状态")

    try:
        next_row = apply_common_phrase_review(
            {
                "approved_content": row.approved_content or "",
                "pending_content": row.pending_content or "",
                "review_status": row.review_status or "none",
                "review_remark": row.review_remark or "",
            },
            status=req_in.status,
            review_remark=req_in.review_remark,
        )
    except ValueError as exc:
        return Fail(code=400, msg=str(exc))

    row.approved_content = next_row["approved_content"]
    row.pending_content = next_row["pending_content"]
    row.review_status = next_row["review_status"]
    row.review_remark = next_row["review_remark"]
    row.reviewed_at = now_local_naive()
    row.reviewed_by = int(CTX_USER_ID.get() or 0) or None
    await row.save(
        update_fields=[
            "approved_content",
            "pending_content",
            "review_status",
            "review_remark",
            "reviewed_at",
            "reviewed_by",
            "updated_at",
        ]
    )
    return Success(msg="审核成功")


@router.get("/bill/list", summary="查看App用户账单列表")
async def list_app_user_bill(
    user_id: int = Query(..., ge=1, description="用户ID"),
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    direction: str = Query("all", description="方向 all/income/expense"),
    biz_type: str = Query(
        "", description="业务类型 recharge/call/gift/withdraw/im_text/call_fee/gift_fee/token_adjust"
    ),
):
    user = await AppUser.filter(id=user_id).first()
    if not user:
        return Fail(code=404, msg="用户不存在")

    recharges = await RechargeOrder.filter(user_id=user_id, status="paid").values(
        "id", "amount", "created_at", "paid_at"
    )
    call_expenses = await CallRecord.filter(
        (Q(payer_user_id=user_id) | (Q(payer_user_id__isnull=True) & Q(caller_id=user_id))) & Q(total_fee__gt=0)
    ).values("id", "caller_id", "callee_id", "payer_user_id", "total_fee", "created_at", "ended_at")
    call_incomes = await CallRecord.filter(
        income_certified_user_id=user_id, certified_user_income_diamonds__gt=0
    ).values(
        "id",
        "caller_id",
        "callee_id",
        "payer_user_id",
        "income_certified_user_id",
        "certified_user_income_diamonds",
        "created_at",
        "income_settled_at",
    )
    call_fee_payer_expenses = await CallRecord.filter(
        (Q(payer_user_id=user_id) | (Q(payer_user_id__isnull=True) & Q(caller_id=user_id)))
        & Q(service_fee_payer_actual_coins__gt=0)
    ).values(
        "id",
        "caller_id",
        "callee_id",
        "payer_user_id",
        "service_fee_payer_actual_coins",
        "created_at",
        "service_fee_payer_settled_at",
    )
    call_fee_income_expenses = await CallRecord.filter(
        income_certified_user_id=user_id,
        service_fee_income_actual_diamonds__gt=0,
    ).values(
        "id",
        "caller_id",
        "callee_id",
        "payer_user_id",
        "income_certified_user_id",
        "service_fee_income_actual_diamonds",
        "created_at",
        "service_fee_income_settled_at",
    )
    gift_expenses = await GiftRecord.filter(sender_id=user_id, total_price__gt=0).values(
        "id", "sender_id", "receiver_id", "gift_name", "total_price", "created_at"
    )
    gift_incomes = await GiftRecord.filter(receiver_id=user_id, certified_user_income_diamonds__gt=0).values(
        "id",
        "sender_id",
        "receiver_id",
        "gift_name",
        "certified_user_income_diamonds",
        "created_at",
    )
    gift_fee_expenses = await GiftRecord.filter(sender_id=user_id, service_fee_sender_actual_coins__gt=0).values(
        "id",
        "sender_id",
        "receiver_id",
        "gift_name",
        "service_fee_sender_actual_coins",
        "created_at",
        "service_fee_sender_settled_at",
    )
    im_text_expenses = await ImTextMessageChargeRecord.filter(sender_id=user_id, price__gt=0).values(
        "id", "sender_id", "receiver_id", "price", "created_at"
    )
    im_text_incomes = await ImTextMessageChargeRecord.filter(
        receiver_id=user_id, certified_user_income_diamonds__gt=0
    ).values(
        "id",
        "sender_id",
        "receiver_id",
        "certified_user_income_diamonds",
        "created_at",
    )
    withdraw_expenses = await WithdrawApply.filter(user_id=user_id, amount__gt=0).values(
        "id", "amount", "status", "created_at"
    )
    token_adjust_records = await AppUserTokenAdjustRecord.filter(app_user_id=user_id, amount__gt=0).values(
        "id",
        "asset_type",
        "action",
        "amount",
        "created_at",
    )

    related_user_ids: set[int] = set()

    for row in call_expenses:
        caller_id = int(row.get("caller_id") or 0)
        callee_id = int(row.get("callee_id") or 0)
        related_user_id = callee_id if caller_id == user_id else caller_id
        if related_user_id > 0:
            related_user_ids.add(related_user_id)
    for row in call_incomes:
        payer_user_id = int(row.get("payer_user_id") or 0)
        caller_id = int(row.get("caller_id") or 0)
        callee_id = int(row.get("callee_id") or 0)
        related_user_id = payer_user_id or caller_id
        if related_user_id == user_id:
            related_user_id = callee_id if callee_id != user_id else caller_id
        if related_user_id > 0:
            related_user_ids.add(related_user_id)
    for row in call_fee_payer_expenses:
        caller_id = int(row.get("caller_id") or 0)
        callee_id = int(row.get("callee_id") or 0)
        related_user_id = callee_id if caller_id == user_id else caller_id
        if related_user_id > 0:
            related_user_ids.add(related_user_id)
    for row in call_fee_income_expenses:
        payer_user_id = int(row.get("payer_user_id") or 0)
        caller_id = int(row.get("caller_id") or 0)
        callee_id = int(row.get("callee_id") or 0)
        related_user_id = payer_user_id or caller_id
        if related_user_id == user_id:
            related_user_id = callee_id if callee_id != user_id else caller_id
        if related_user_id > 0:
            related_user_ids.add(related_user_id)
    for row in gift_expenses:
        related_user_id = int(row.get("receiver_id") or 0)
        if related_user_id > 0:
            related_user_ids.add(related_user_id)
    for row in gift_incomes:
        related_user_id = int(row.get("sender_id") or 0)
        if related_user_id > 0:
            related_user_ids.add(related_user_id)
    for row in gift_fee_expenses:
        related_user_id = int(row.get("receiver_id") or 0)
        if related_user_id > 0:
            related_user_ids.add(related_user_id)
    for row in im_text_expenses:
        related_user_id = int(row.get("receiver_id") or 0)
        if related_user_id > 0:
            related_user_ids.add(related_user_id)
    for row in im_text_incomes:
        related_user_id = int(row.get("sender_id") or 0)
        if related_user_id > 0:
            related_user_ids.add(related_user_id)

    user_map: dict[int, AppUser] = {}
    if related_user_ids:
        users = await AppUser.filter(id__in=list(related_user_ids)).all()
        user_map = {int(item.id): item for item in users}

    def _resolve_related_user(uid: int) -> tuple[int | None, str]:
        if uid <= 0:
            return None, "平台"
        user_row = user_map.get(uid)
        if not user_row:
            return uid, f"用户{uid}"
        nickname = (user_row.nickname or "").strip() or (user_row.phone or "").strip() or f"用户{uid}"
        return uid, nickname

    bills = []
    for row in recharges:
        amount = decimal_to_float_2(row.get("amount"))
        bills.append(
            {
                "id": f"recharge_{row['id']}",
                "biz_id": row["id"],
                "biz_type": "recharge",
                "title": "充值",
                "direction": "income",
                "is_income": True,
                "asset_type": "coins",
                "amount": amount,
                "related_user_id": None,
                "related_user_nickname": "平台",
                "created_at": _format_bill_dt(row.get("paid_at") or row.get("created_at")),
            }
        )
    for row in call_expenses:
        amount = decimal_to_float_2(row.get("total_fee"))
        caller_id = int(row.get("caller_id") or 0)
        callee_id = int(row.get("callee_id") or 0)
        related_user_id = callee_id if caller_id == user_id else caller_id
        related_id, related_nickname = _resolve_related_user(related_user_id)
        bills.append(
            {
                "id": f"call_expense_{row['id']}",
                "biz_id": row["id"],
                "biz_type": "call",
                "title": "通话消费",
                "direction": "expense",
                "is_income": False,
                "asset_type": "coins",
                "amount": amount,
                "related_user_id": related_id,
                "related_user_nickname": related_nickname,
                "created_at": _format_bill_dt(row.get("ended_at") or row.get("created_at")),
            }
        )
    for row in call_incomes:
        amount = decimal_to_float_2(row.get("certified_user_income_diamonds"))
        payer_user_id = int(row.get("payer_user_id") or 0)
        caller_id = int(row.get("caller_id") or 0)
        callee_id = int(row.get("callee_id") or 0)
        related_user_id = payer_user_id or caller_id
        if related_user_id == user_id:
            related_user_id = callee_id if callee_id != user_id else caller_id
        related_id, related_nickname = _resolve_related_user(related_user_id)
        bills.append(
            {
                "id": f"call_income_{row['id']}",
                "biz_id": row["id"],
                "biz_type": "call",
                "title": "通话收益",
                "direction": "income",
                "is_income": True,
                "asset_type": "diamonds",
                "amount": amount,
                "related_user_id": related_id,
                "related_user_nickname": related_nickname,
                "created_at": _format_bill_dt(row.get("income_settled_at") or row.get("created_at")),
            }
        )
    for row in call_fee_payer_expenses:
        amount = decimal_to_float_2(row.get("service_fee_payer_actual_coins"))
        caller_id = int(row.get("caller_id") or 0)
        callee_id = int(row.get("callee_id") or 0)
        related_user_id = callee_id if caller_id == user_id else caller_id
        related_id, related_nickname = _resolve_related_user(related_user_id)
        bills.append(
            {
                "id": f"call_fee_payer_{row['id']}",
                "biz_id": row["id"],
                "biz_type": "call_fee",
                "title": "通话手续费",
                "direction": "expense",
                "is_income": False,
                "asset_type": "coins",
                "amount": amount,
                "related_user_id": related_id,
                "related_user_nickname": related_nickname,
                "created_at": _format_bill_dt(row.get("service_fee_payer_settled_at") or row.get("created_at")),
            }
        )
    for row in call_fee_income_expenses:
        amount = decimal_to_float_2(row.get("service_fee_income_actual_diamonds"))
        payer_user_id = int(row.get("payer_user_id") or 0)
        caller_id = int(row.get("caller_id") or 0)
        callee_id = int(row.get("callee_id") or 0)
        related_user_id = payer_user_id or caller_id
        if related_user_id == user_id:
            related_user_id = callee_id if callee_id != user_id else caller_id
        related_id, related_nickname = _resolve_related_user(related_user_id)
        bills.append(
            {
                "id": f"call_fee_income_{row['id']}",
                "biz_id": row["id"],
                "biz_type": "call_fee",
                "title": "通话收益手续费",
                "direction": "expense",
                "is_income": False,
                "asset_type": "diamonds",
                "amount": amount,
                "related_user_id": related_id,
                "related_user_nickname": related_nickname,
                "created_at": _format_bill_dt(row.get("service_fee_income_settled_at") or row.get("created_at")),
            }
        )
    for row in gift_expenses:
        amount = decimal_to_float_2(row.get("total_price"))
        gift_name = (row.get("gift_name") or "").strip()
        related_id, related_nickname = _resolve_related_user(int(row.get("receiver_id") or 0))
        bills.append(
            {
                "id": f"gift_expense_{row['id']}",
                "biz_id": row["id"],
                "biz_type": "gift",
                "title": f"送礼消费{f'({gift_name})' if gift_name else ''}",
                "direction": "expense",
                "is_income": False,
                "asset_type": "coins",
                "amount": amount,
                "related_user_id": related_id,
                "related_user_nickname": related_nickname,
                "created_at": _format_bill_dt(row.get("created_at")),
            }
        )
    for row in gift_incomes:
        amount = decimal_to_float_2(row.get("certified_user_income_diamonds"))
        gift_name = (row.get("gift_name") or "").strip()
        related_id, related_nickname = _resolve_related_user(int(row.get("sender_id") or 0))
        bills.append(
            {
                "id": f"gift_income_{row['id']}",
                "biz_id": row["id"],
                "biz_type": "gift",
                "title": f"礼物收益{f'({gift_name})' if gift_name else ''}",
                "direction": "income",
                "is_income": True,
                "asset_type": "diamonds",
                "amount": amount,
                "related_user_id": related_id,
                "related_user_nickname": related_nickname,
                "created_at": _format_bill_dt(row.get("created_at")),
            }
        )
    for row in gift_fee_expenses:
        amount = decimal_to_float_2(row.get("service_fee_sender_actual_coins"))
        gift_name = (row.get("gift_name") or "").strip()
        related_id, related_nickname = _resolve_related_user(int(row.get("receiver_id") or 0))
        bills.append(
            {
                "id": f"gift_fee_{row['id']}",
                "biz_id": row["id"],
                "biz_type": "gift_fee",
                "title": f"礼物手续费{f'({gift_name})' if gift_name else ''}",
                "direction": "expense",
                "is_income": False,
                "asset_type": "coins",
                "amount": amount,
                "related_user_id": related_id,
                "related_user_nickname": related_nickname,
                "created_at": _format_bill_dt(row.get("service_fee_sender_settled_at") or row.get("created_at")),
            }
        )
    for row in im_text_expenses:
        amount = int(row.get("price") or 0)
        related_id, related_nickname = _resolve_related_user(int(row.get("receiver_id") or 0))
        bills.append(
            {
                "id": f"im_text_expense_{row['id']}",
                "biz_id": row["id"],
                "biz_type": "im_text",
                "title": "文字聊天",
                "direction": "expense",
                "is_income": False,
                "asset_type": "coins",
                "amount": amount,
                "related_user_id": related_id,
                "related_user_nickname": related_nickname,
                "created_at": _format_bill_dt(row.get("created_at")),
            }
        )
    for row in im_text_incomes:
        amount = decimal_to_float_2(row.get("certified_user_income_diamonds"))
        related_id, related_nickname = _resolve_related_user(int(row.get("sender_id") or 0))
        bills.append(
            {
                "id": f"im_text_income_{row['id']}",
                "biz_id": row["id"],
                "biz_type": "im_text",
                "title": "文字聊天收益",
                "direction": "income",
                "is_income": True,
                "asset_type": "diamonds",
                "amount": amount,
                "related_user_id": related_id,
                "related_user_nickname": related_nickname,
                "created_at": _format_bill_dt(row.get("created_at")),
            }
        )
    for row in withdraw_expenses:
        amount = decimal_to_float_2(row.get("amount"))
        status = (row.get("status") or "").strip()
        bills.append(
            {
                "id": f"withdraw_{row['id']}",
                "biz_id": row["id"],
                "biz_type": "withdraw",
                "title": f"提现申请{f'({status})' if status else ''}",
                "direction": "expense",
                "is_income": False,
                "asset_type": "diamonds",
                "amount": amount,
                "related_user_id": None,
                "related_user_nickname": "平台",
                "created_at": _format_bill_dt(row.get("created_at")),
            }
        )
    for row in token_adjust_records:
        amount = decimal_to_float_2(row.get("amount"))
        asset_type = (row.get("asset_type") or "").strip()
        action = (row.get("action") or "").strip()
        is_income = action == "increase"
        title_map = {
            ("coins", "increase"): "后台增加金币",
            ("coins", "decrease"): "后台扣除金币",
            ("diamonds", "increase"): "后台增加钻石",
            ("diamonds", "decrease"): "后台扣除钻石",
        }
        bills.append(
            {
                "id": f"token_adjust_{row['id']}",
                "biz_id": row["id"],
                "biz_type": "token_adjust",
                "title": title_map.get((asset_type, action), "后台调整"),
                "direction": "income" if is_income else "expense",
                "is_income": is_income,
                "asset_type": asset_type,
                "amount": amount,
                "related_user_id": None,
                "related_user_nickname": "后台调整",
                "created_at": _format_bill_dt(row.get("created_at")),
            }
        )

    normalized_direction = (direction or "all").strip().lower()
    if normalized_direction not in {"all", "income", "expense"}:
        return Fail(code=400, msg="direction 仅支持 all/income/expense")

    normalized_biz_type = (biz_type or "").strip().lower()
    if normalized_biz_type:
        allowed_types = {"recharge", "call", "gift", "withdraw", "im_text", "call_fee", "gift_fee", "token_adjust"}
        if normalized_biz_type not in allowed_types:
            return Fail(
                code=400, msg="biz_type 仅支持 recharge/call/gift/withdraw/im_text/call_fee/gift_fee/token_adjust"
            )

    filtered = bills
    if normalized_direction == "income":
        filtered = [item for item in filtered if item["is_income"]]
    elif normalized_direction == "expense":
        filtered = [item for item in filtered if not item["is_income"]]
    if normalized_biz_type:
        filtered = [item for item in filtered if item["biz_type"] == normalized_biz_type]

    income_coins_total = sum(
        _amount_decimal(item["amount"]) for item in filtered if item["is_income"] and item.get("asset_type") == "coins"
    )
    income_diamonds_total = sum(
        _amount_decimal(item["amount"])
        for item in filtered
        if item["is_income"] and item.get("asset_type") == "diamonds"
    )
    expense_coins_total = sum(
        _amount_decimal(item["amount"])
        for item in filtered
        if (not item["is_income"]) and item.get("asset_type") == "coins"
    )
    expense_diamonds_total = sum(
        _amount_decimal(item["amount"])
        for item in filtered
        if (not item["is_income"]) and item.get("asset_type") == "diamonds"
    )

    filtered.sort(
        key=lambda item: item.get("created_at") or "",
        reverse=True,
    )
    total = len(filtered)
    offset = (page - 1) * page_size
    rows = filtered[offset : offset + page_size]
    has_more = total > offset + page_size
    return SuccessExtra(
        data=rows,
        total=total,
        current=page,
        has_more=has_more,
        income_coins_total=decimal_to_float_2(income_coins_total),
        income_diamonds_total=decimal_to_float_2(income_diamonds_total),
        expense_coins_total=decimal_to_float_2(expense_coins_total),
        expense_diamonds_total=decimal_to_float_2(expense_diamonds_total),
    )
