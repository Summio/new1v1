from types import SimpleNamespace

import pytest

from app.api.v1.app import call as call_api


def test_resolve_billing_free_seconds_prefers_snapshot() -> None:
    record = SimpleNamespace(billing_free_seconds=35)
    assert call_api._resolve_billing_free_seconds(record, 10) == 35


def test_resolve_billing_free_seconds_fallback_to_default() -> None:
    record = SimpleNamespace()
    assert call_api._resolve_billing_free_seconds(record, 10) == 10


def test_calc_due_minutes_with_free_zero_when_under_free_seconds() -> None:
    assert call_api._calc_due_minutes_with_free(duration_seconds=9, free_seconds_before_billing=10) == 0


def test_calc_due_minutes_with_free_rounds_up_by_total_duration_after_gate() -> None:
    assert call_api._calc_due_minutes_with_free(duration_seconds=12, free_seconds_before_billing=10) == 1
    assert call_api._calc_due_minutes_with_free(duration_seconds=61, free_seconds_before_billing=10) == 2


@pytest.mark.asyncio
async def test_resolve_payer_id_with_snapshot_prefers_snapshot() -> None:
    record = SimpleNamespace(payer_user_id=2001)
    payer_id = await call_api._resolve_payer_id_with_snapshot(record)
    assert payer_id == 2001


@pytest.mark.asyncio
async def test_resolve_payer_id_with_snapshot_fallback_dynamic(monkeypatch: pytest.MonkeyPatch) -> None:
    async def fake_resolve(_record: object) -> int:
        return 3002

    monkeypatch.setattr(call_api, "_resolve_payer_id", fake_resolve)
    record = SimpleNamespace(payer_user_id=None)
    payer_id = await call_api._resolve_payer_id_with_snapshot(record)
    assert payer_id == 3002
