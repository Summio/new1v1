from datetime import date, datetime
from pathlib import Path

from fastapi import APIRouter, File, Query, UploadFile
from tortoise.expressions import Q

from app.models import AppUser, CallRecord, GiftRecord, ImTextMessageChargeRecord, RechargeOrder, WithdrawApply
from app.schemas.app_user import AnchorApplyReviewIn, AppUserAdminUpdateIn
from app.schemas.base import Fail, Success, SuccessExtra
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


@router.get("/list", summary="查看App用户列表")
async def list_app_user(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    phone: str = Query("", description="手机号"),
    nickname: str = Query("", description="昵称"),
    status: str = Query("", description="状态 normal/banned"),
    is_anchor: bool | None = Query(None, description="是否主播"),
    anchor_apply_status: str = Query("", description="主播申请状态 none/pending/approved/rejected"),
    gender: str = Query("", description="性别 male/female/secret"),
    location_city: str = Query("", description="所在地(省-市)"),
):
    q = Q()
    if phone:
        q &= Q(phone__contains=phone)
    if nickname:
        q &= Q(nickname__contains=nickname)
    if status:
        q &= Q(status=status)
    if is_anchor is not None:
        q &= Q(is_anchor=is_anchor)
    if anchor_apply_status:
        q &= Q(anchor_apply_status=anchor_apply_status)
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
        row["anchor_apply_face_image"] = to_relative_media_url(row.get("anchor_apply_face_image"))
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
    data["anchor_apply_face_image"] = to_relative_media_url(data.get("anchor_apply_face_image"))
    data["album_photos"] = _normalize_album(data.get("album_photos"))
    album = data.get("album_photos")
    data["album_count"] = len(album) if isinstance(album, list) else 0
    return Success(data=data)


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
        v = req_in.location_city.strip()
        update_data["location_city"] = v or None
    if req_in.status is not None:
        update_data["status"] = req_in.status
    if req_in.is_anchor is not None:
        update_data["is_anchor"] = req_in.is_anchor
        if req_in.is_anchor:
            update_data["anchor_apply_status"] = "approved"
            update_data["anchor_reviewed_at"] = datetime.now()
    if req_in.anchor_intro is not None:
        v = req_in.anchor_intro.strip()
        update_data["anchor_intro"] = v or None
    if req_in.anchor_tags is not None:
        tags: list[str] = []
        for item in req_in.anchor_tags:
            if not isinstance(item, str):
                continue
            tag = item.strip()
            if tag:
                tags.append(tag)
        update_data["anchor_tags"] = tags
    if req_in.anchor_call_price is not None:
        update_data["anchor_call_price"] = req_in.anchor_call_price
    if req_in.anchor_reject_reason is not None:
        v = req_in.anchor_reject_reason.strip()
        update_data["anchor_reject_reason"] = v or None
    if req_in.anchor_apply_face_image is not None:
        v = to_relative_media_url(req_in.anchor_apply_face_image)
        update_data["anchor_apply_face_image"] = v or None
    if req_in.anchor_apply_status is not None:
        reject_reason = (req_in.anchor_reject_reason or "").strip()
        target_face_image = to_relative_media_url(
            req_in.anchor_apply_face_image
            if req_in.anchor_apply_face_image is not None
            else app_user.anchor_apply_face_image
        )
        update_data["anchor_apply_status"] = req_in.anchor_apply_status
        update_data["anchor_reviewed_at"] = datetime.now()
        if req_in.anchor_apply_status == "approved":
            if not target_face_image:
                return Fail(code=400, msg="申请正面照缺失，无法通过审核")
            update_data["is_anchor"] = True
            update_data["anchor_reject_reason"] = None
        elif req_in.anchor_apply_status in {"none", "rejected"}:
            update_data["is_anchor"] = False
        if req_in.anchor_apply_status == "rejected":
            if not reject_reason:
                return Fail(code=400, msg="驳回时必须填写驳回原因")
            update_data["anchor_reject_reason"] = reject_reason
        if req_in.anchor_apply_status == "pending":
            update_data["anchor_apply_at"] = datetime.now()
            update_data["anchor_reviewed_at"] = None
            update_data["anchor_reject_reason"] = None
    if req_in.album_photos is not None:
        update_data["album_photos"] = target_album
    if req_in.cover_url is not None:
        cover = to_relative_media_url(req_in.cover_url)
        if cover and cover not in target_album:
            return Fail(code=400, msg="封面必须从相册中选择")
        update_data["cover_url"] = cover or None
    elif req_in.album_photos is not None:
        current_cover = (app_user.cover_url or "").strip()
        if current_cover and current_cover in target_album:
            update_data["cover_url"] = current_cover
        else:
            update_data["cover_url"] = target_album[0] if target_album else None

    if update_data:
        await AppUser.filter(id=req_in.id).update(**update_data)
    return Success(msg="更新成功")


@router.post("/anchor-apply/review", summary="审核主播申请")
async def review_anchor_apply(req_in: AnchorApplyReviewIn):
    app_user = await AppUser.filter(id=req_in.id).first()
    if not app_user:
        return Fail(code=404, msg="用户不存在")

    if req_in.status == "approved":
        if not to_relative_media_url(app_user.anchor_apply_face_image):
            return Fail(code=400, msg="申请正面照缺失，无法通过审核")
        await AppUser.filter(id=app_user.id).update(
            is_anchor=True,
            anchor_apply_status="approved",
            anchor_reject_reason=None,
            anchor_reviewed_at=datetime.now(),
        )
        return Success(msg="审核通过")

    reject_reason = (req_in.reject_reason or "").strip()
    if not reject_reason:
        return Fail(code=400, msg="驳回时必须填写驳回原因")
    await AppUser.filter(id=app_user.id).update(
        is_anchor=False,
        anchor_apply_status="rejected",
        anchor_reject_reason=reject_reason,
        anchor_reviewed_at=datetime.now(),
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


@router.get("/bill/list", summary="查看App用户账单列表")
async def list_app_user_bill(
    user_id: int = Query(..., ge=1, description="用户ID"),
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    direction: str = Query("all", description="方向 all/income/expense"),
    biz_type: str = Query("", description="业务类型 recharge/call/gift/withdraw/im_text"),
):
    user = await AppUser.filter(id=user_id).first()
    if not user:
        return Fail(code=404, msg="用户不存在")

    recharges = await RechargeOrder.filter(user_id=user_id, status="paid").values(
        "id", "amount", "created_at", "paid_at"
    )
    call_expenses = await CallRecord.filter(
        (
            Q(payer_user_id=user_id)
            | (Q(payer_user_id__isnull=True) & Q(caller_id=user_id))
        )
        & Q(total_fee__gt=0)
    ).values("id", "caller_id", "callee_id", "payer_user_id", "total_fee", "created_at", "ended_at")
    call_incomes = await CallRecord.filter(
        income_anchor_user_id=user_id, anchor_income_diamonds__gt=0
    ).values(
        "id",
        "caller_id",
        "callee_id",
        "payer_user_id",
        "income_anchor_user_id",
        "anchor_income_diamonds",
        "created_at",
        "income_settled_at",
    )
    gift_expenses = await GiftRecord.filter(sender_id=user_id, total_price__gt=0).values(
        "id", "sender_id", "receiver_id", "gift_name", "total_price", "created_at"
    )
    gift_incomes = await GiftRecord.filter(
        receiver_id=user_id, anchor_income_diamonds__gt=0
    ).values(
        "id",
        "sender_id",
        "receiver_id",
        "gift_name",
        "anchor_income_diamonds",
        "created_at",
    )
    im_text_expenses = await ImTextMessageChargeRecord.filter(sender_id=user_id, price__gt=0).values(
        "id", "sender_id", "receiver_id", "price", "created_at"
    )
    im_text_incomes = await ImTextMessageChargeRecord.filter(
        receiver_id=user_id, anchor_income_diamonds__gt=0
    ).values(
        "id",
        "sender_id",
        "receiver_id",
        "anchor_income_diamonds",
        "created_at",
    )
    withdraw_expenses = await WithdrawApply.filter(user_id=user_id, amount__gt=0).values(
        "id", "amount", "status", "created_at"
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
    for row in gift_expenses:
        related_user_id = int(row.get("receiver_id") or 0)
        if related_user_id > 0:
            related_user_ids.add(related_user_id)
    for row in gift_incomes:
        related_user_id = int(row.get("sender_id") or 0)
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
        amount = int(row.get("amount") or 0)
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
        amount = int(row.get("total_fee") or 0)
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
        amount = int(row.get("anchor_income_diamonds") or 0)
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
                "created_at": _format_bill_dt(
                    row.get("income_settled_at") or row.get("created_at")
                ),
            }
        )
    for row in gift_expenses:
        amount = int(row.get("total_price") or 0)
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
        amount = int(row.get("anchor_income_diamonds") or 0)
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
        amount = int(row.get("anchor_income_diamonds") or 0)
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
        amount = int(row.get("amount") or 0)
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

    normalized_direction = (direction or "all").strip().lower()
    if normalized_direction not in {"all", "income", "expense"}:
        return Fail(code=400, msg="direction 仅支持 all/income/expense")

    normalized_biz_type = (biz_type or "").strip().lower()
    if normalized_biz_type:
        allowed_types = {"recharge", "call", "gift", "withdraw", "im_text"}
        if normalized_biz_type not in allowed_types:
            return Fail(code=400, msg="biz_type 仅支持 recharge/call/gift/withdraw/im_text")

    filtered = bills
    if normalized_direction == "income":
        filtered = [item for item in filtered if item["is_income"]]
    elif normalized_direction == "expense":
        filtered = [item for item in filtered if not item["is_income"]]
    if normalized_biz_type:
        filtered = [item for item in filtered if item["biz_type"] == normalized_biz_type]

    income_coins_total = sum(
        item["amount"]
        for item in filtered
        if item["is_income"] and item.get("asset_type") == "coins"
    )
    income_diamonds_total = sum(
        item["amount"]
        for item in filtered
        if item["is_income"] and item.get("asset_type") == "diamonds"
    )
    expense_coins_total = sum(
        item["amount"]
        for item in filtered
        if (not item["is_income"]) and item.get("asset_type") == "coins"
    )
    expense_diamonds_total = sum(
        item["amount"]
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
        income_coins_total=income_coins_total,
        income_diamonds_total=income_diamonds_total,
        expense_coins_total=expense_coins_total,
        expense_diamonds_total=expense_diamonds_total,
    )
