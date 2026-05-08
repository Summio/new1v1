import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.services import call_income_service  # noqa: E402


DEFAULT_CERTIFIED_USER_SHARE_BPS = call_income_service.DEFAULT_CERTIFIED_USER_SHARE_BPS
calc_certified_user_income_diamonds = call_income_service.calc_certified_user_income_diamonds
get_certified_user_share_bps = call_income_service.get_certified_user_share_bps
resolve_income_certified_user_id = call_income_service.resolve_income_certified_user_id


def test_calc_certified_user_income_uses_bps_and_rounds_down() -> None:
    assert calc_certified_user_income_diamonds(100, 5000) == 50
    assert calc_certified_user_income_diamonds(101, 5000) == 50
    assert calc_certified_user_income_diamonds(101, 5250) == 53


def test_calc_certified_user_income_clamps_invalid_bounds() -> None:
    assert calc_certified_user_income_diamonds(100, -1) == 0
    assert calc_certified_user_income_diamonds(100, 10001) == 100
    assert calc_certified_user_income_diamonds(-100, 5000) == 0


@pytest.mark.asyncio
async def test_get_certified_user_share_bps_falls_back_and_clamps(monkeypatch: pytest.MonkeyPatch) -> None:
    values = iter(["bad", "-1", "10001", "7000"])

    async def fake_get_value(_key: str, _default: str) -> str:
        return next(values)

    monkeypatch.setattr(call_income_service.SystemConfig, "get_value", fake_get_value)

    assert await get_certified_user_share_bps() == DEFAULT_CERTIFIED_USER_SHARE_BPS
    assert await get_certified_user_share_bps() == 0
    assert await get_certified_user_share_bps() == 10000
    assert await get_certified_user_share_bps() == 7000


def test_resolve_income_certified_user_id_only_returns_non_payer_certified_user() -> None:
    user = SimpleNamespace(id=1001, is_certified_user=False)
    certified_user = SimpleNamespace(id=2002, is_certified_user=True)

    assert resolve_income_certified_user_id([user, certified_user], payer_id=1001) == 2002
    assert resolve_income_certified_user_id([user, certified_user], payer_id=2002) == 0
    assert resolve_income_certified_user_id([user], payer_id=1001) == 0


def test_snapshot_share_bps_falls_back_for_dirty_value() -> None:
    assert (
        call_income_service._resolve_snapshot_share_bps(SimpleNamespace(certified_user_share_bps="bad"))  # noqa: SLF001
        == DEFAULT_CERTIFIED_USER_SHARE_BPS
    )
    assert call_income_service._resolve_snapshot_share_bps(SimpleNamespace(certified_user_share_bps="-1")) == 0  # noqa: SLF001
    assert (
        call_income_service._resolve_snapshot_share_bps(SimpleNamespace(certified_user_share_bps="10001"))  # noqa: SLF001
        == 10000
    )
