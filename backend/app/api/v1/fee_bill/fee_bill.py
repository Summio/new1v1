from datetime import date, datetime
from decimal import Decimal

from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.models import AppUser, CallRecord, GiftRecord
from app.schemas.base import Fail, SuccessExtra
from app.services.gift_income_service import decimal_to_float_2

router = APIRouter()


def _parse_dt(dt_str: str, field_name: str) -> datetime:
    raw = (dt_str or "").strip()
    if not raw:
        raise ValueError(f"{field_name} 不能为空")
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"{field_name} 格式错误，要求 YYYY-MM-DD HH:mm:ss 或 ISO8601") from exc


def _format_dt(value: datetime | date | None) -> str:
    if not value:
        return ""
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    return value.isoformat()


def _money(value: Decimal | int | float | str | None) -> float:
    return decimal_to_float_2(value)


def _bps_percent(value: int | None) -> float:
    try:
        return round(int(value or 0) / 100, 2)
    except Exception:  # noqa: BLE001
        return 0.0


def _user_brief(user_map: dict[int, AppUser], user_id: int | None) -> dict:
    uid = int(user_id or 0)
    if uid <= 0:
        return {"id": None, "nickname": "", "phone": ""}
    user = user_map.get(uid)
    if not user:
        return {"id": uid, "nickname": f"用户{uid}", "phone": ""}
    return {
        "id": uid,
        "nickname": (user.nickname or user.phone or f"用户{uid}"),
        "phone": user.phone or "",
    }


async def _load_user_map(user_ids: set[int]) -> dict[int, AppUser]:
    normalized_ids = [int(uid) for uid in user_ids if int(uid or 0) > 0]
    if not normalized_ids:
        return {}
    users = await AppUser.filter(id__in=normalized_ids).all()
    return {int(user.id): user for user in users}


@router.get("/list", summary="手续费账单列表")
async def list_fee_bill(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    biz_type: str = Query("", description="业务类型 call/gift"),
    status: str = Query("", description="手续费状态"),
    user_id: int | None = Query(None, ge=1, description="用户ID"),
    record_id: int | None = Query(None, ge=1, description="业务记录ID"),
    start_time: str = Query("", description="开始时间(创建时间起)"),
    end_time: str = Query("", description="结束时间(创建时间止)"),
):
    normalized_biz_type = (biz_type or "").strip().lower()
    if normalized_biz_type and normalized_biz_type not in {"call", "gift"}:
        return Fail(code=400, msg="biz_type 仅支持 call/gift")

    normalized_status = (status or "").strip()
    try:
        started_at = _parse_dt(start_time, "start_time") if start_time else None
        ended_at = _parse_dt(end_time, "end_time") if end_time else None
    except ValueError as exc:
        return Fail(code=400, msg=str(exc))

    rows: list[dict] = []
    user_ids: set[int] = set()

    if normalized_biz_type in {"", "call"}:
        call_q = Q(service_fee_payer_status__isnull=False) | Q(service_fee_income_status__isnull=False)
        if normalized_status:
            call_q &= Q(service_fee_payer_status=normalized_status) | Q(service_fee_income_status=normalized_status)
        if user_id is not None:
            call_q &= (
                Q(caller_id=user_id)
                | Q(callee_id=user_id)
                | Q(payer_user_id=user_id)
                | Q(income_certified_user_id=user_id)
            )
        if record_id is not None:
            call_q &= Q(id=record_id)
        if started_at is not None:
            call_q &= Q(created_at__gte=started_at)
        if ended_at is not None:
            call_q &= Q(created_at__lte=ended_at)

        call_records = await CallRecord.filter(call_q).all()
        for row in call_records:
            user_ids.add(int(row.caller_id or 0))
            user_ids.add(int(row.callee_id or 0))
            user_ids.add(int(row.payer_user_id or 0))
            user_ids.add(int(row.income_certified_user_id or 0))
            rows.append(
                {
                    "id": f"call_{row.id}",
                    "biz_type": "call",
                    "record_id": int(row.id),
                    "created_at": _format_dt(row.created_at),
                    "caller_id": int(row.caller_id or 0),
                    "callee_id": int(row.callee_id or 0),
                    "payer_user_id": int(row.payer_user_id or 0) or None,
                    "income_certified_user_id": int(row.income_certified_user_id or 0) or None,
                    "call_price": int(row.call_price or 0),
                    "threshold_minutes": int(row.service_fee_threshold_minutes or 0),
                    "rate_bps": int(row.service_fee_rate_bps or 0),
                    "rate_percent": _bps_percent(row.service_fee_rate_bps),
                    "payer_rate_bps": int(
                        getattr(row, "service_fee_payer_rate_bps", row.service_fee_rate_bps) or row.service_fee_rate_bps or 0
                    ),
                    "payer_rate_percent": _bps_percent(
                        getattr(row, "service_fee_payer_rate_bps", row.service_fee_rate_bps)
                        or row.service_fee_rate_bps
                    ),
                    "income_rate_bps": int(
                        getattr(row, "service_fee_income_rate_bps", row.service_fee_rate_bps)
                        or row.service_fee_rate_bps
                        or 0
                    ),
                    "income_rate_percent": _bps_percent(
                        getattr(row, "service_fee_income_rate_bps", row.service_fee_rate_bps)
                        or row.service_fee_rate_bps
                    ),
                    "processed_chargeable_minutes": int(row.service_fee_processed_chargeable_minutes or 0),
                    "payer_expected_coins": _money(row.service_fee_payer_expected_coins),
                    "payer_actual_coins": _money(row.service_fee_payer_actual_coins),
                    "payer_status": row.service_fee_payer_status,
                    "payer_settled_at": _format_dt(row.service_fee_payer_settled_at),
                    "income_expected_diamonds": _money(row.service_fee_income_expected_diamonds),
                    "income_actual_diamonds": _money(row.service_fee_income_actual_diamonds),
                    "income_status": row.service_fee_income_status,
                    "income_settled_at": _format_dt(row.service_fee_income_settled_at),
                }
            )

    if normalized_biz_type in {"", "gift"}:
        gift_q = Q(service_fee_sender_status__isnull=False)
        if normalized_status:
            gift_q &= Q(service_fee_sender_status=normalized_status)
        if user_id is not None:
            gift_q &= Q(sender_id=user_id) | Q(receiver_id=user_id)
        if record_id is not None:
            gift_q &= Q(id=record_id)
        if started_at is not None:
            gift_q &= Q(created_at__gte=started_at)
        if ended_at is not None:
            gift_q &= Q(created_at__lte=ended_at)

        gift_records = await GiftRecord.filter(gift_q).all()
        for row in gift_records:
            user_ids.add(int(row.sender_id or 0))
            user_ids.add(int(row.receiver_id or 0))
            rows.append(
                {
                    "id": f"gift_{row.id}",
                    "biz_type": "gift",
                    "record_id": int(row.id),
                    "created_at": _format_dt(row.created_at),
                    "sender_id": int(row.sender_id or 0),
                    "receiver_id": int(row.receiver_id or 0),
                    "gift_id": int(row.gift_id or 0),
                    "gift_name": row.gift_name or "",
                    "gift_unit_price": int(row.price or 0),
                    "threshold_coins": int(row.service_fee_threshold_coins or 0),
                    "rate_bps": int(row.service_fee_rate_bps or 0),
                    "rate_percent": _bps_percent(row.service_fee_rate_bps),
                    "sender_expected_coins": _money(row.service_fee_sender_expected_coins),
                    "sender_actual_coins": _money(row.service_fee_sender_actual_coins),
                    "sender_status": row.service_fee_sender_status,
                    "sender_settled_at": _format_dt(row.service_fee_sender_settled_at),
                }
            )

    user_map = await _load_user_map(user_ids)
    for row in rows:
        if row["biz_type"] == "call":
            row["caller"] = _user_brief(user_map, row.get("caller_id"))
            row["callee"] = _user_brief(user_map, row.get("callee_id"))
            row["payer_user"] = _user_brief(user_map, row.get("payer_user_id"))
            row["income_user"] = _user_brief(user_map, row.get("income_certified_user_id"))
        else:
            row["sender"] = _user_brief(user_map, row.get("sender_id"))
            row["receiver"] = _user_brief(user_map, row.get("receiver_id"))

    rows.sort(key=lambda item: item.get("created_at") or "", reverse=True)
    total = len(rows)
    offset = (page - 1) * page_size
    page_rows = rows[offset : offset + page_size]
    return SuccessExtra(
        data=page_rows,
        total=total,
        page=page,
        page_size=page_size,
        current=page,
        has_more=total > offset + page_size,
    )
