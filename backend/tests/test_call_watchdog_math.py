from app.core.call_watchdog import (
    _next_due_second,
    _resolve_billing_free_seconds,
    _resolve_payer_user_id,
)


def test_next_due_second_first_charge_starts_at_free_boundary() -> None:
    assert _next_due_second(deducted_minutes=0, free_seconds_before_billing=10) == 10


def test_next_due_second_respects_free_offset_for_subsequent_minutes() -> None:
    assert _next_due_second(deducted_minutes=1, free_seconds_before_billing=10) == 70
    assert _next_due_second(deducted_minutes=2, free_seconds_before_billing=10) == 130


def test_next_due_second_degrades_to_minute_boundary_when_free_is_zero() -> None:
    assert _next_due_second(deducted_minutes=1, free_seconds_before_billing=0) == 60
    assert _next_due_second(deducted_minutes=2, free_seconds_before_billing=0) == 120


def test_resolve_billing_free_seconds_uses_snapshot_when_present() -> None:
    assert _resolve_billing_free_seconds(30, 10) == 30


def test_resolve_billing_free_seconds_falls_back_to_default() -> None:
    assert _resolve_billing_free_seconds(None, 10) == 10


def test_resolve_payer_user_id_returns_none_for_empty_snapshot() -> None:
    assert _resolve_payer_user_id(None) is None


def test_resolve_payer_user_id_returns_snapshot_value() -> None:
    assert _resolve_payer_user_id(123) == 123
