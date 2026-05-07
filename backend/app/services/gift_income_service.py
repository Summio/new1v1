from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP

from app.utils.parse import clamp_int, safe_parse_int

DEFAULT_GIFT_ANCHOR_SHARE_BPS = 5000
MAX_GIFT_ANCHOR_SHARE_BPS = 10000
DECIMAL_2 = Decimal("0.01")


def quantize_decimal_2(value: Decimal | int | str | None) -> Decimal:
    try:
        amount = Decimal(str(value if value is not None else "0"))
    except Exception:  # noqa: BLE001
        amount = Decimal("0")
    return amount.quantize(DECIMAL_2, rounding=ROUND_HALF_UP)


def decimal_to_float_2(value: Decimal | int | str | None) -> float:
    return float(quantize_decimal_2(value))


def calc_gift_anchor_income_diamonds(
    total_price: int,
    anchor_share_bps: int,
) -> Decimal:
    amount = max(0, int(total_price or 0))
    bps = clamp_int(int(anchor_share_bps or 0), 0, MAX_GIFT_ANCHOR_SHARE_BPS)
    income = Decimal(amount) * Decimal(bps) / Decimal(MAX_GIFT_ANCHOR_SHARE_BPS)
    return quantize_decimal_2(income)


async def get_gift_anchor_share_bps() -> int:
    from app.models.system_config import SystemConfig

    raw = await SystemConfig.get_value(
        "gift_anchor_share_bps",
        str(DEFAULT_GIFT_ANCHOR_SHARE_BPS),
    )
    return clamp_int(
        safe_parse_int(raw, DEFAULT_GIFT_ANCHOR_SHARE_BPS),
        0,
        MAX_GIFT_ANCHOR_SHARE_BPS,
    )
