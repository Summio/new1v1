import sys
from decimal import Decimal
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))

from app.services.gift_income_service import (  # noqa: E402
    DEFAULT_GIFT_CERTIFIED_USER_SHARE_BPS,
    calc_gift_certified_user_income_diamonds,
    decimal_to_float_2,
)


def test_calc_gift_certified_user_income_keeps_two_decimals_for_min_price() -> None:
    assert calc_gift_certified_user_income_diamonds(1, 5000) == Decimal("0.50")


def test_calc_gift_certified_user_income_uses_configured_bps_and_rounds_to_cents() -> None:
    assert calc_gift_certified_user_income_diamonds(1, 3333) == Decimal("0.33")
    assert calc_gift_certified_user_income_diamonds(1, 6667) == Decimal("0.67")
    assert calc_gift_certified_user_income_diamonds(99, 5250) == Decimal("51.98")


def test_calc_gift_certified_user_income_clamps_invalid_values() -> None:
    assert calc_gift_certified_user_income_diamonds(-1, 5000) == Decimal("0.00")
    assert calc_gift_certified_user_income_diamonds(100, -1) == Decimal("0.00")
    assert calc_gift_certified_user_income_diamonds(100, 10001) == Decimal("100.00")


def test_default_gift_certified_user_share_is_half() -> None:
    assert DEFAULT_GIFT_CERTIFIED_USER_SHARE_BPS == 5000


def test_decimal_to_float_2_normalizes_response_values() -> None:
    assert decimal_to_float_2(Decimal("0.5")) == 0.5
    assert decimal_to_float_2(1) == 1.0
    assert decimal_to_float_2(None) == 0.0

