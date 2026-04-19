from app.core.call_watchdog import (
    _build_coins_decrement_expr,
    _calc_due_minutes,
    _clamp_renew_grace_seconds,
    _next_due_second,
    _resolve_billing_free_seconds,
    _resolve_payer_user_id,
)
from tortoise.expressions import CombinedExpression, F


def test_next_due_second_first_charge_starts_at_free_boundary() -> None:
    assert _next_due_second(deducted_minutes=0, free_seconds_before_billing=10) == 10


def test_next_due_second_subsequent_minutes_follow_natural_minute_boundary() -> None:
    assert _next_due_second(deducted_minutes=1, free_seconds_before_billing=10) == 60
    assert _next_due_second(deducted_minutes=2, free_seconds_before_billing=10) == 120


def test_next_due_second_degrades_to_minute_boundary_when_free_is_zero() -> None:
    assert _next_due_second(deducted_minutes=0, free_seconds_before_billing=0) == 0
    assert _next_due_second(deducted_minutes=1, free_seconds_before_billing=0) == 60
    assert _next_due_second(deducted_minutes=2, free_seconds_before_billing=0) == 120


def test_calc_due_minutes_free_gate_then_by_total_duration() -> None:
    assert _calc_due_minutes(duration_seconds=9, free_seconds_before_billing=10) == 0
    assert _calc_due_minutes(duration_seconds=12, free_seconds_before_billing=10) == 1
    assert _calc_due_minutes(duration_seconds=61, free_seconds_before_billing=10) == 2


def test_clamp_renew_grace_seconds_not_exceed_five() -> None:
    assert _clamp_renew_grace_seconds(-1) == 0
    assert _clamp_renew_grace_seconds(0) == 0
    assert _clamp_renew_grace_seconds(5) == 5
    assert _clamp_renew_grace_seconds(25) == 5


def test_resolve_billing_free_seconds_uses_snapshot_when_present() -> None:
    assert _resolve_billing_free_seconds(30, 10) == 30


def test_resolve_billing_free_seconds_falls_back_to_default() -> None:
    assert _resolve_billing_free_seconds(None, 10) == 10


def test_resolve_payer_user_id_returns_none_for_empty_snapshot() -> None:
    assert _resolve_payer_user_id(None) is None


def test_resolve_payer_user_id_returns_snapshot_value() -> None:
    assert _resolve_payer_user_id(123) == 123


def test_build_coins_decrement_expr_uses_f_expression() -> None:
    expr = _build_coins_decrement_expr(120)
    assert isinstance(expr, CombinedExpression)
    assert isinstance(expr.left, F)
    assert expr.left.name == "coins"
    assert getattr(expr.right, "value", None) == 120
