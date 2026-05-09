from pathlib import Path
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


def test_dialing_recomputes_billing_snapshot_after_user_locks() -> None:
    content = call_api.__file__
    assert content is not None
    source = Path(content).read_text(encoding="utf-8")

    assert "locked_caller = await AppUser.filter" in source
    assert "locked_target_user = await AppUser.filter" in source
    assert "caller_is_certified_user = bool(locked_caller.is_certified_user)" in source
    assert "callee_is_certified_user = bool(locked_target_user.is_certified_user)" in source
    assert "call_price = int(locked_caller.certified_call_price or 0)" in source
    assert "call_price = int(locked_target_user.certified_call_price or 0)" in source
    assert "locked_caller.coins < call_price" in source


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


@pytest.mark.asyncio
async def test_resolve_payer_id_for_certified_pair_returns_caller(monkeypatch: pytest.MonkeyPatch) -> None:
    users = [
        SimpleNamespace(id=1001, is_certified_user=True),
        SimpleNamespace(id=2002, is_certified_user=True),
    ]

    class FakeQuery:
        def select_for_update(self) -> "FakeQuery":
            return self

        async def all(self) -> list[SimpleNamespace]:
            return users

    class FakeAppUser:
        @staticmethod
        def filter(**_kwargs: object) -> FakeQuery:
            return FakeQuery()

    monkeypatch.setattr(call_api, "AppUser", FakeAppUser)

    payer_id = await call_api._resolve_payer_id(SimpleNamespace(caller_id=1001, callee_id=2002))
    assert payer_id == 1001
