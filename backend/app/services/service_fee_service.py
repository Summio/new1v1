from __future__ import annotations

from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

from app.utils.parse import clamp_int, safe_parse_bool, safe_parse_int

DECIMAL_2 = Decimal("0.01")
MAX_RATE_BPS = 10000
DEFAULT_CALL_SERVICE_FEE_THRESHOLD_MINUTES = 0
DEFAULT_CALL_SERVICE_FEE_RATE_BPS = 0
DEFAULT_CALL_SERVICE_FEE_PAYER_RATE_BPS = 0
DEFAULT_CALL_SERVICE_FEE_INCOME_RATE_BPS = 0
DEFAULT_GIFT_SERVICE_FEE_THRESHOLD_COINS = 0
DEFAULT_GIFT_SERVICE_FEE_RATE_BPS = 0


@dataclass(frozen=True)
class CallServiceFeeConfig:
    enabled: bool
    threshold_minutes: int
    payer_rate_bps: int
    income_rate_bps: int


@dataclass(frozen=True)
class GiftServiceFeeConfig:
    enabled: bool
    threshold_coins: int
    rate_bps: int


@dataclass(frozen=True)
class CallServiceFeeFinalState:
    chargeable_minutes: int
    payer_expected_coins: Decimal
    payer_actual_coins: Decimal
    payer_refund_coins: Decimal
    payer_status: str | None
    income_expected_diamonds: Decimal
    income_actual_diamonds: Decimal
    income_status: str | None


@dataclass(frozen=True)
class CallServiceFeeAdjustmentResult:
    payer_balance_changed: bool
    payer_charged_additional_coins: Decimal
    payer_refund_coins: Decimal


def quantize_decimal_2(value: Decimal | int | float | str | None) -> Decimal:
    try:
        amount = Decimal(str(value if value is not None else "0"))
    except Exception:  # noqa: BLE001
        amount = Decimal("0")
    return amount.quantize(DECIMAL_2, rounding=ROUND_HALF_UP)


def calc_incremental_chargeable_minutes(
    *,
    previous_processed: int,
    deducted_minutes: int,
    threshold_minutes: int,
) -> int:
    processed = max(0, int(previous_processed or 0))
    due_minutes = max(0, int(deducted_minutes or 0))
    threshold = max(0, int(threshold_minutes or 0))
    total_chargeable = max(due_minutes - threshold, 0)
    return max(total_chargeable - processed, 0)


def calc_service_fee_decimal(base_amount: int | Decimal, rate_bps: int) -> Decimal:
    amount = quantize_decimal_2(base_amount)
    if amount <= 0:
        return Decimal("0.00")
    bps = clamp_int(int(rate_bps or 0), 0, MAX_RATE_BPS)
    if bps <= 0:
        return Decimal("0.00")
    return quantize_decimal_2(amount * Decimal(bps) / Decimal(MAX_RATE_BPS))


def calc_call_chargeable_minutes(*, deducted_minutes: int, threshold_minutes: int) -> int:
    due_minutes = max(0, int(deducted_minutes or 0))
    threshold = max(0, int(threshold_minutes or 0))
    return max(due_minutes - threshold, 0)


def calc_call_service_fee_for_minutes(
    *,
    call_price: int,
    chargeable_minutes: int,
    rate_bps: int,
) -> Decimal:
    minutes = max(0, int(chargeable_minutes or 0))
    if minutes <= 0:
        return Decimal("0.00")
    per_minute_fee = calc_service_fee_decimal(max(0, int(call_price or 0)), rate_bps)
    if per_minute_fee <= 0:
        return Decimal("0.00")
    return quantize_decimal_2(per_minute_fee * Decimal(minutes))


def calc_gift_service_fee(*, unit_price: int, rate_bps: int) -> Decimal:
    return calc_service_fee_decimal(max(0, int(unit_price or 0)), rate_bps)


def apply_call_service_fee_config_snapshot(call_record: Any, config: CallServiceFeeConfig) -> None:
    payer_rate_bps = clamp_int(int(config.payer_rate_bps or 0), 0, MAX_RATE_BPS)
    income_rate_bps = clamp_int(int(config.income_rate_bps or 0), 0, MAX_RATE_BPS)
    enabled = bool(config.enabled and (payer_rate_bps > 0 or income_rate_bps > 0))
    call_record.service_fee_threshold_minutes = int(config.threshold_minutes or 0) if enabled else 0
    call_record.service_fee_rate_bps = payer_rate_bps if enabled else 0
    call_record.service_fee_payer_rate_bps = payer_rate_bps if enabled else 0
    call_record.service_fee_income_rate_bps = income_rate_bps if enabled else 0
    call_record.service_fee_processed_chargeable_minutes = 0
    call_record.service_fee_payer_expected_coins = Decimal("0.00")
    call_record.service_fee_payer_actual_coins = Decimal("0.00")
    call_record.service_fee_payer_status = None
    call_record.service_fee_payer_settled_at = None
    call_record.service_fee_income_expected_diamonds = Decimal("0.00")
    call_record.service_fee_income_actual_diamonds = Decimal("0.00")
    call_record.service_fee_income_status = None
    call_record.service_fee_income_settled_at = None


def resolve_call_service_fee_payer_status(
    *,
    expected_amount: Decimal | int | float | str | None,
    actual_amount: Decimal | int | float | str | None,
) -> str | None:
    expected = quantize_decimal_2(expected_amount)
    actual = quantize_decimal_2(actual_amount)
    if expected <= 0:
        return None
    if actual <= 0:
        return "skipped_insufficient"
    if actual < expected:
        return "charged_partial"
    return "charged_full"


def calc_net_call_income_diamonds(
    gross_income_diamonds: Decimal | int | float | str | None,
    service_fee_diamonds: Decimal | int | float | str | None,
) -> Decimal:
    gross = quantize_decimal_2(gross_income_diamonds)
    fee = quantize_decimal_2(service_fee_diamonds)
    net = gross - fee
    if net <= 0:
        return Decimal("0.00")
    return quantize_decimal_2(net)


def resolve_call_service_fee_income_per_minute(
    *,
    call_price: int,
    certified_user_share_bps: int,
) -> Decimal:
    from app.services.call_income_service import calc_certified_user_income_diamonds

    gross_income = calc_certified_user_income_diamonds(max(0, int(call_price or 0)), certified_user_share_bps)
    return quantize_decimal_2(gross_income)


def calc_call_income_service_fee_for_minutes(
    *,
    call_price: int,
    certified_user_share_bps: int,
    chargeable_minutes: int,
    rate_bps: int,
) -> Decimal:
    per_minute_income = resolve_call_service_fee_income_per_minute(
        call_price=call_price,
        certified_user_share_bps=certified_user_share_bps,
    )
    minutes = max(0, int(chargeable_minutes or 0))
    if per_minute_income <= 0 or minutes <= 0:
        return Decimal("0.00")
    per_minute_fee = calc_service_fee_decimal(per_minute_income, rate_bps)
    if per_minute_fee <= 0:
        return Decimal("0.00")
    return quantize_decimal_2(per_minute_fee * Decimal(minutes))


def build_call_service_fee_final_state(
    *,
    call_price: int,
    certified_user_share_bps: int,
    deducted_minutes: int,
    threshold_minutes: int,
    payer_actual_coins: Decimal | int | float | str | None,
    rate_bps: int | None = None,
    payer_rate_bps: int | None = None,
    income_rate_bps: int | None = None,
) -> CallServiceFeeFinalState:
    fallback_rate_bps = clamp_int(int(rate_bps or 0), 0, MAX_RATE_BPS)
    resolved_payer_rate_bps = clamp_int(
        int(fallback_rate_bps if payer_rate_bps is None else payer_rate_bps or 0),
        0,
        MAX_RATE_BPS,
    )
    resolved_income_rate_bps = clamp_int(
        int(fallback_rate_bps if income_rate_bps is None else income_rate_bps or 0),
        0,
        MAX_RATE_BPS,
    )
    chargeable_minutes = calc_call_chargeable_minutes(
        deducted_minutes=deducted_minutes,
        threshold_minutes=threshold_minutes,
    )
    payer_expected_coins = calc_call_service_fee_for_minutes(
        call_price=call_price,
        chargeable_minutes=chargeable_minutes,
        rate_bps=resolved_payer_rate_bps,
    )
    income_expected_diamonds = calc_call_income_service_fee_for_minutes(
        call_price=call_price,
        certified_user_share_bps=certified_user_share_bps,
        chargeable_minutes=chargeable_minutes,
        rate_bps=resolved_income_rate_bps,
    )
    raw_payer_actual_coins = quantize_decimal_2(payer_actual_coins)
    payer_actual_coins_final = raw_payer_actual_coins
    if payer_expected_coins <= 0:
        payer_actual_coins_final = Decimal("0.00")
    elif raw_payer_actual_coins > payer_expected_coins:
        payer_actual_coins_final = payer_expected_coins
    payer_refund_coins = quantize_decimal_2(raw_payer_actual_coins - payer_actual_coins_final)
    if payer_refund_coins < 0:
        payer_refund_coins = Decimal("0.00")
    payer_status = resolve_call_service_fee_payer_status(
        expected_amount=payer_expected_coins,
        actual_amount=payer_actual_coins_final,
    )
    income_actual_diamonds = income_expected_diamonds if income_expected_diamonds > 0 else Decimal("0.00")
    income_status = "charged" if income_actual_diamonds > 0 else None
    return CallServiceFeeFinalState(
        chargeable_minutes=chargeable_minutes,
        payer_expected_coins=quantize_decimal_2(payer_expected_coins),
        payer_actual_coins=quantize_decimal_2(payer_actual_coins_final),
        payer_refund_coins=quantize_decimal_2(payer_refund_coins),
        payer_status=payer_status,
        income_expected_diamonds=quantize_decimal_2(income_expected_diamonds),
        income_actual_diamonds=quantize_decimal_2(income_actual_diamonds),
        income_status=income_status,
    )


async def apply_call_service_fee_final_adjustment(
    *,
    call_record: Any,
    conn: Any,
    payer_id: int | None,
    payer: Any | None = None,
) -> CallServiceFeeAdjustmentResult:
    from app.core.time_utils import now_local_naive
    from app.models import AppUser

    call_price = max(0, int(getattr(call_record, "call_price", 0) or 0))
    threshold_minutes = max(0, int(getattr(call_record, "service_fee_threshold_minutes", 0) or 0))
    legacy_rate_bps = clamp_int(int(getattr(call_record, "service_fee_rate_bps", 0) or 0), 0, MAX_RATE_BPS)
    payer_rate_bps = clamp_int(
        int(getattr(call_record, "service_fee_payer_rate_bps", legacy_rate_bps) or legacy_rate_bps),
        0,
        MAX_RATE_BPS,
    )
    income_rate_bps = clamp_int(
        int(getattr(call_record, "service_fee_income_rate_bps", legacy_rate_bps) or legacy_rate_bps),
        0,
        MAX_RATE_BPS,
    )
    certified_user_share_bps = clamp_int(
        safe_parse_int(getattr(call_record, "certified_user_share_bps", 0), 0),
        0,
        MAX_RATE_BPS,
    )
    final_deducted_minutes = max(0, int(getattr(call_record, "deducted_minutes", 0) or 0))
    final_chargeable_minutes = calc_call_chargeable_minutes(
        deducted_minutes=final_deducted_minutes,
        threshold_minutes=threshold_minutes,
    )
    processed_chargeable_minutes = max(
        0,
        int(getattr(call_record, "service_fee_processed_chargeable_minutes", 0) or 0),
    )
    payer_actual_coins = quantize_decimal_2(getattr(call_record, "service_fee_payer_actual_coins", 0))
    payer_expected_coins = quantize_decimal_2(getattr(call_record, "service_fee_payer_expected_coins", 0))
    income_expected_diamonds = quantize_decimal_2(getattr(call_record, "service_fee_income_expected_diamonds", 0))
    payer_charged_additional_coins = Decimal("0.00")
    payer_balance_changed = False

    if (payer_rate_bps > 0 or income_rate_bps > 0) and final_chargeable_minutes > processed_chargeable_minutes:
        delta_minutes = final_chargeable_minutes - processed_chargeable_minutes
        payer_fee_per_minute = calc_call_service_fee_for_minutes(
            call_price=call_price,
            chargeable_minutes=1,
            rate_bps=payer_rate_bps,
        )
        income_fee_per_minute = calc_call_income_service_fee_for_minutes(
            call_price=call_price,
            certified_user_share_bps=certified_user_share_bps,
            chargeable_minutes=1,
            rate_bps=income_rate_bps,
        )
        locked_payer = payer
        if payer_fee_per_minute > 0 and (locked_payer is None) and payer_id and int(payer_id) > 0:
            locked_payer = await AppUser.filter(id=int(payer_id)).using_db(conn).select_for_update().first()
        payer_balance = quantize_decimal_2(getattr(locked_payer, "coins", 0)) if locked_payer else Decimal("0.00")

        for _ in range(delta_minutes):
            payer_expected_coins = quantize_decimal_2(payer_expected_coins + payer_fee_per_minute)
            income_expected_diamonds = quantize_decimal_2(income_expected_diamonds + income_fee_per_minute)
            if payer_fee_per_minute > 0 and locked_payer and payer_balance >= payer_fee_per_minute:
                payer_balance = quantize_decimal_2(payer_balance - payer_fee_per_minute)
                payer_actual_coins = quantize_decimal_2(payer_actual_coins + payer_fee_per_minute)
                payer_charged_additional_coins = quantize_decimal_2(
                    payer_charged_additional_coins + payer_fee_per_minute
                )
                payer_balance_changed = True

        if locked_payer and payer_balance_changed:
            locked_payer.coins = payer_balance
            await locked_payer.save(using_db=conn, update_fields=["coins"])
            payer = locked_payer

    final_state = build_call_service_fee_final_state(
        call_price=call_price,
        certified_user_share_bps=certified_user_share_bps,
        deducted_minutes=final_deducted_minutes,
        threshold_minutes=threshold_minutes,
        payer_actual_coins=payer_actual_coins,
        payer_rate_bps=payer_rate_bps,
        income_rate_bps=income_rate_bps,
    )

    if final_state.payer_refund_coins > 0 and payer_id and int(payer_id) > 0:
        from app.models import AppUser

        locked_payer = payer
        if locked_payer is None:
            locked_payer = await AppUser.filter(id=int(payer_id)).using_db(conn).select_for_update().first()
        if locked_payer:
            locked_payer.coins = quantize_decimal_2(
                quantize_decimal_2(getattr(locked_payer, "coins", 0)) + final_state.payer_refund_coins
            )
            await locked_payer.save(using_db=conn, update_fields=["coins"])
            payer_balance_changed = True

    call_record.service_fee_processed_chargeable_minutes = final_state.chargeable_minutes
    call_record.service_fee_payer_expected_coins = final_state.payer_expected_coins
    call_record.service_fee_payer_actual_coins = final_state.payer_actual_coins
    call_record.service_fee_payer_status = final_state.payer_status
    call_record.service_fee_payer_settled_at = now_local_naive() if final_state.payer_status else None
    call_record.service_fee_income_expected_diamonds = final_state.income_expected_diamonds
    call_record.service_fee_income_actual_diamonds = final_state.income_actual_diamonds
    call_record.service_fee_income_status = final_state.income_status
    call_record.service_fee_income_settled_at = now_local_naive() if final_state.income_status else None

    return CallServiceFeeAdjustmentResult(
        payer_balance_changed=payer_balance_changed,
        payer_charged_additional_coins=quantize_decimal_2(payer_charged_additional_coins),
        payer_refund_coins=final_state.payer_refund_coins,
    )


async def get_call_service_fee_config() -> CallServiceFeeConfig:
    from app.models.system_config import SystemConfig

    enabled_raw = await SystemConfig.get_value("call_service_fee_enabled", "0")
    legacy_rate_raw = await SystemConfig.get_value(
        "call_service_fee_rate_bps",
        str(DEFAULT_CALL_SERVICE_FEE_RATE_BPS),
    )
    threshold_raw = await SystemConfig.get_value(
        "call_service_fee_threshold_minutes",
        str(DEFAULT_CALL_SERVICE_FEE_THRESHOLD_MINUTES),
    )
    payer_rate_raw = await SystemConfig.get_value(
        "call_service_fee_payer_rate_bps",
        legacy_rate_raw,
    )
    income_rate_raw = await SystemConfig.get_value(
        "call_service_fee_income_rate_bps",
        legacy_rate_raw,
    )
    return CallServiceFeeConfig(
        enabled=safe_parse_bool(enabled_raw, False),
        threshold_minutes=max(0, safe_parse_int(threshold_raw, DEFAULT_CALL_SERVICE_FEE_THRESHOLD_MINUTES)),
        payer_rate_bps=clamp_int(
            safe_parse_int(payer_rate_raw, DEFAULT_CALL_SERVICE_FEE_PAYER_RATE_BPS),
            0,
            MAX_RATE_BPS,
        ),
        income_rate_bps=clamp_int(
            safe_parse_int(income_rate_raw, DEFAULT_CALL_SERVICE_FEE_INCOME_RATE_BPS),
            0,
            MAX_RATE_BPS,
        ),
    )


async def get_gift_service_fee_config() -> GiftServiceFeeConfig:
    from app.models.system_config import SystemConfig

    enabled_raw = await SystemConfig.get_value("gift_service_fee_enabled", "0")
    threshold_raw = await SystemConfig.get_value(
        "gift_service_fee_threshold_coins",
        str(DEFAULT_GIFT_SERVICE_FEE_THRESHOLD_COINS),
    )
    rate_raw = await SystemConfig.get_value(
        "gift_service_fee_rate_bps",
        str(DEFAULT_GIFT_SERVICE_FEE_RATE_BPS),
    )
    return GiftServiceFeeConfig(
        enabled=safe_parse_bool(enabled_raw, False),
        threshold_coins=max(0, safe_parse_int(threshold_raw, DEFAULT_GIFT_SERVICE_FEE_THRESHOLD_COINS)),
        rate_bps=clamp_int(safe_parse_int(rate_raw, DEFAULT_GIFT_SERVICE_FEE_RATE_BPS), 0, MAX_RATE_BPS),
    )
