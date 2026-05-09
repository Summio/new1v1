from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from tortoise.expressions import F

from app.core.time_utils import now_local_naive
from app.models import AppUser, SystemConfig
from app.utils.parse import clamp_int, safe_parse_int

DEFAULT_CERTIFIED_USER_SHARE_BPS = 5000
MAX_CERTIFIED_USER_SHARE_BPS = 10000


@dataclass(frozen=True)
class CallIncomeSettlement:
    certified_user_id: int = 0
    certified_user_income_diamonds: int = 0
    settled: bool = False


def calc_certified_user_income_diamonds(total_fee: int, certified_user_share_bps: int) -> int:
    amount = max(0, int(total_fee or 0))
    bps = clamp_int(int(certified_user_share_bps or 0), 0, MAX_CERTIFIED_USER_SHARE_BPS)
    return amount * bps // MAX_CERTIFIED_USER_SHARE_BPS


async def get_certified_user_share_bps() -> int:
    raw = await SystemConfig.get_value(
        "call_certified_user_share_bps",
        str(DEFAULT_CERTIFIED_USER_SHARE_BPS),
    )
    return clamp_int(
        safe_parse_int(raw, DEFAULT_CERTIFIED_USER_SHARE_BPS),
        0,
        MAX_CERTIFIED_USER_SHARE_BPS,
    )


def resolve_income_certified_user_id(users: list[AppUser], payer_id: int | None) -> int:
    if payer_id is None or int(payer_id) <= 0:
        return 0
    return next(
        (
            int(user.id)
            for user in users
            if bool(user.is_certified_user) and int(user.id) != int(payer_id)
        ),
        0,
    )


def _resolve_snapshot_share_bps(call_record: Any) -> int:
    raw = getattr(call_record, "certified_user_share_bps", None)
    if raw is None:
        return DEFAULT_CERTIFIED_USER_SHARE_BPS
    return clamp_int(
        safe_parse_int(raw, DEFAULT_CERTIFIED_USER_SHARE_BPS),
        0,
        MAX_CERTIFIED_USER_SHARE_BPS,
    )


async def settle_call_certified_user_income_once(
    *,
    call_record: Any,
    conn: Any,
    total_fee: int,
    payer_id: int | None = None,
    participants: list[AppUser] | None = None,
) -> CallIncomeSettlement:
    if getattr(call_record, "income_settled_at", None) is not None:
        return CallIncomeSettlement()

    final_fee = max(0, int(total_fee or 0))
    certified_user_share_bps = _resolve_snapshot_share_bps(call_record)
    income_certified_user_id = int(getattr(call_record, "income_certified_user_id", 0) or 0)
    if income_certified_user_id <= 0 and participants is not None:
        income_certified_user_id = resolve_income_certified_user_id(participants, payer_id)

    call_record.income_certified_user_id = income_certified_user_id or None
    call_record.certified_user_share_bps = certified_user_share_bps
    call_record.certified_user_income_diamonds = 0

    if final_fee <= 0 or income_certified_user_id <= 0:
        return CallIncomeSettlement(certified_user_id=income_certified_user_id)

    certified_user_income = calc_certified_user_income_diamonds(final_fee, certified_user_share_bps)
    if certified_user_income <= 0:
        return CallIncomeSettlement(certified_user_id=income_certified_user_id)

    certified_user = await AppUser.filter(id=income_certified_user_id).using_db(conn).select_for_update().first()
    if not certified_user:
        return CallIncomeSettlement(certified_user_id=income_certified_user_id)

    await AppUser.filter(id=income_certified_user_id).using_db(conn).update(diamonds=F("diamonds") + certified_user_income)
    call_record.certified_user_income_diamonds = certified_user_income
    call_record.income_settled_at = now_local_naive()
    return CallIncomeSettlement(
        certified_user_id=income_certified_user_id,
        certified_user_income_diamonds=certified_user_income,
        settled=True,
    )


