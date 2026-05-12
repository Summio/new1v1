import sys
from decimal import Decimal
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.services import service_fee_service  # noqa: E402

calc_incremental_chargeable_minutes = service_fee_service.calc_incremental_chargeable_minutes
calc_service_fee_decimal = service_fee_service.calc_service_fee_decimal
calc_call_service_fee_for_minutes = service_fee_service.calc_call_service_fee_for_minutes
calc_gift_service_fee = service_fee_service.calc_gift_service_fee
calc_net_call_income_diamonds = service_fee_service.calc_net_call_income_diamonds
build_call_service_fee_final_state = service_fee_service.build_call_service_fee_final_state
apply_call_service_fee_config_snapshot = service_fee_service.apply_call_service_fee_config_snapshot
CallServiceFeeConfig = service_fee_service.CallServiceFeeConfig


def test_incremental_chargeable_minutes_only_counts_minutes_above_threshold() -> None:
    assert calc_incremental_chargeable_minutes(previous_processed=0, deducted_minutes=2, threshold_minutes=2) == 0
    assert calc_incremental_chargeable_minutes(previous_processed=0, deducted_minutes=3, threshold_minutes=2) == 1
    assert calc_incremental_chargeable_minutes(previous_processed=1, deducted_minutes=5, threshold_minutes=2) == 2


def test_incremental_chargeable_minutes_never_goes_negative() -> None:
    assert calc_incremental_chargeable_minutes(previous_processed=3, deducted_minutes=4, threshold_minutes=2) == 0
    assert calc_incremental_chargeable_minutes(previous_processed=-1, deducted_minutes=1, threshold_minutes=2) == 0


def test_calc_service_fee_decimal_quantizes_to_two_decimals() -> None:
    assert calc_service_fee_decimal(101, 2500) == Decimal("25.25")
    assert calc_service_fee_decimal(99, 333) == Decimal("3.30")
    assert calc_service_fee_decimal(-100, 5000) == Decimal("0.00")


def test_calc_call_service_fee_for_minutes_multiplies_by_minutes() -> None:
    assert calc_call_service_fee_for_minutes(call_price=100, chargeable_minutes=2, rate_bps=1500) == Decimal("30.00")
    assert calc_call_service_fee_for_minutes(call_price=100, chargeable_minutes=0, rate_bps=1500) == Decimal("0.00")


def test_call_service_fee_rounds_each_minute_before_multiplying() -> None:
    assert calc_call_service_fee_for_minutes(call_price=1, chargeable_minutes=2, rate_bps=50) == Decimal("0.02")
    assert service_fee_service.calc_call_income_service_fee_for_minutes(
        call_price=1,
        certified_user_share_bps=10000,
        chargeable_minutes=2,
        rate_bps=50,
    ) == Decimal("0.02")


def test_calc_gift_service_fee_uses_single_unit_price() -> None:
    assert calc_gift_service_fee(unit_price=600, rate_bps=500) == Decimal("30.00")
    assert calc_gift_service_fee(unit_price=0, rate_bps=500) == Decimal("0.00")


def test_calc_net_call_income_diamonds_subtracts_fee_and_clamps_at_zero() -> None:
    assert calc_net_call_income_diamonds(50, Decimal("2.50")) == Decimal("47.50")
    assert calc_net_call_income_diamonds(50, Decimal("99.00")) == Decimal("0.00")


def test_build_call_service_fee_final_state_reconciles_over_collected_actual_amount() -> None:
    result = build_call_service_fee_final_state(
        call_price=100,
        certified_user_share_bps=5000,
        deducted_minutes=5,
        threshold_minutes=2,
        rate_bps=1000,
        payer_actual_coins=Decimal("40.00"),
    )

    assert result.chargeable_minutes == 3
    assert result.payer_expected_coins == Decimal("30.00")
    assert result.payer_actual_coins == Decimal("30.00")
    assert result.payer_refund_coins == Decimal("10.00")
    assert result.payer_status == "charged_full"
    assert result.income_expected_diamonds == Decimal("15.00")
    assert result.income_actual_diamonds == Decimal("15.00")
    assert result.income_status == "charged"


def test_build_call_service_fee_final_state_marks_skipped_when_actual_is_zero() -> None:
    result = build_call_service_fee_final_state(
        call_price=120,
        certified_user_share_bps=5000,
        deducted_minutes=4,
        threshold_minutes=1,
        rate_bps=500,
        payer_actual_coins=Decimal("0"),
    )

    assert result.chargeable_minutes == 3
    assert result.payer_expected_coins == Decimal("18.00")
    assert result.payer_actual_coins == Decimal("0.00")
    assert result.payer_refund_coins == Decimal("0.00")
    assert result.payer_status == "skipped_insufficient"
    assert result.income_expected_diamonds == Decimal("9.00")
    assert result.income_actual_diamonds == Decimal("9.00")
    assert result.income_status == "charged"


def test_build_call_service_fee_final_state_uses_separate_call_payer_and_income_rates() -> None:
    result = build_call_service_fee_final_state(
        call_price=100,
        certified_user_share_bps=5000,
        deducted_minutes=4,
        threshold_minutes=1,
        payer_rate_bps=1000,
        income_rate_bps=2000,
        payer_actual_coins=Decimal("30.00"),
    )

    assert result.chargeable_minutes == 3
    assert result.payer_expected_coins == Decimal("30.00")
    assert result.payer_actual_coins == Decimal("30.00")
    assert result.income_expected_diamonds == Decimal("30.00")
    assert result.income_actual_diamonds == Decimal("30.00")


def test_apply_call_service_fee_config_snapshot_stores_separate_rates() -> None:
    class DummyCallRecord:
        pass

    call_record = DummyCallRecord()

    apply_call_service_fee_config_snapshot(
        call_record,
        CallServiceFeeConfig(
            enabled=True,
            threshold_minutes=2,
            payer_rate_bps=1000,
            income_rate_bps=2500,
        ),
    )

    assert call_record.service_fee_threshold_minutes == 2
    assert call_record.service_fee_payer_rate_bps == 1000
    assert call_record.service_fee_income_rate_bps == 2500
