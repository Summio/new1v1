from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from tortoise.expressions import F

from app.core.time_utils import now_local_naive
from app.models import AppUser, SystemConfig
from app.utils.parse import clamp_int, safe_parse_int

DEFAULT_ANCHOR_SHARE_BPS = 5000
MAX_ANCHOR_SHARE_BPS = 10000


@dataclass(frozen=True)
class CallIncomeSettlement:
    anchor_user_id: int = 0
    anchor_income_diamonds: int = 0
    settled: bool = False


def calc_anchor_income_diamonds(total_fee: int, anchor_share_bps: int) -> int:
    amount = max(0, int(total_fee or 0))
    bps = clamp_int(int(anchor_share_bps or 0), 0, MAX_ANCHOR_SHARE_BPS)
    return amount * bps // MAX_ANCHOR_SHARE_BPS


async def get_anchor_share_bps() -> int:
    raw = await SystemConfig.get_value(
        "call_anchor_share_bps",
        str(DEFAULT_ANCHOR_SHARE_BPS),
    )
    return clamp_int(
        safe_parse_int(raw, DEFAULT_ANCHOR_SHARE_BPS),
        0,
        MAX_ANCHOR_SHARE_BPS,
    )


def resolve_income_anchor_id(users: list[AppUser], payer_id: int | None) -> int:
    if payer_id is None or int(payer_id) <= 0:
        return 0
    return next(
        (
            int(user.id)
            for user in users
            if bool(user.is_anchor) and int(user.id) != int(payer_id)
        ),
        0,
    )


def _resolve_snapshot_share_bps(call_record: Any) -> int:
    raw = getattr(call_record, "anchor_share_bps", None)
    if raw is None:
        return DEFAULT_ANCHOR_SHARE_BPS
    return clamp_int(
        safe_parse_int(raw, DEFAULT_ANCHOR_SHARE_BPS),
        0,
        MAX_ANCHOR_SHARE_BPS,
    )


async def settle_call_anchor_income_once(
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
    anchor_share_bps = _resolve_snapshot_share_bps(call_record)
    income_anchor_id = int(getattr(call_record, "income_anchor_user_id", 0) or 0)
    if income_anchor_id <= 0 and participants is not None:
        income_anchor_id = resolve_income_anchor_id(participants, payer_id)

    call_record.income_anchor_user_id = income_anchor_id or None
    call_record.anchor_share_bps = anchor_share_bps
    call_record.anchor_income_diamonds = 0

    if final_fee <= 0 or income_anchor_id <= 0:
        return CallIncomeSettlement(anchor_user_id=income_anchor_id)

    anchor_income = calc_anchor_income_diamonds(final_fee, anchor_share_bps)
    if anchor_income <= 0:
        return CallIncomeSettlement(anchor_user_id=income_anchor_id)

    anchor = (
        await AppUser.filter(id=income_anchor_id)
        .using_db(conn)
        .select_for_update()
        .first()
    )
    if not anchor:
        return CallIncomeSettlement(anchor_user_id=income_anchor_id)

    await AppUser.filter(id=income_anchor_id).using_db(conn).update(
        diamonds=F("diamonds") + anchor_income
    )
    call_record.anchor_income_diamonds = anchor_income
    call_record.income_settled_at = now_local_naive()
    return CallIncomeSettlement(
        anchor_user_id=income_anchor_id,
        anchor_income_diamonds=anchor_income,
        settled=True,
    )
