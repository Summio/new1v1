import importlib.util
from pathlib import Path
import sys
from types import ModuleType, SimpleNamespace

BACKEND_ROOT = Path(__file__).resolve().parents[1]

import pytest

core_module = ModuleType("app.core")
time_utils_module = ModuleType("app.core.time_utils")
time_utils_module.now_local_naive = lambda: None
models_module = ModuleType("app.models")
models_module.AppUser = object
models_module.SystemConfig = SimpleNamespace(get_value=None)
utils_module = ModuleType("app.utils")
parse_module = ModuleType("app.utils.parse")
parse_module.clamp_int = lambda value, min_value, max_value: min(max(value, min_value), max_value)


def _safe_parse_int(raw: object, default: int) -> int:
    try:
        return int(str(raw).strip())
    except (TypeError, ValueError):
        return default


parse_module.safe_parse_int = _safe_parse_int
tortoise_module = ModuleType("tortoise")
expressions_module = ModuleType("tortoise.expressions")
expressions_module.F = lambda value: value

sys.modules.setdefault("app", ModuleType("app"))
sys.modules["app.core"] = core_module
sys.modules["app.core.time_utils"] = time_utils_module
sys.modules["app.models"] = models_module
sys.modules["app.utils"] = utils_module
sys.modules["app.utils.parse"] = parse_module
sys.modules["tortoise"] = tortoise_module
sys.modules["tortoise.expressions"] = expressions_module

MODULE_PATH = BACKEND_ROOT / "app" / "services" / "call_income_service.py"
SPEC = importlib.util.spec_from_file_location("call_income_service_under_test", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load call_income_service module for test")
call_income_service = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = call_income_service
SPEC.loader.exec_module(call_income_service)

DEFAULT_ANCHOR_SHARE_BPS = call_income_service.DEFAULT_ANCHOR_SHARE_BPS
calc_anchor_income_diamonds = call_income_service.calc_anchor_income_diamonds
get_anchor_share_bps = call_income_service.get_anchor_share_bps
resolve_income_anchor_id = call_income_service.resolve_income_anchor_id


def test_calc_anchor_income_uses_bps_and_rounds_down() -> None:
    assert calc_anchor_income_diamonds(100, 5000) == 50
    assert calc_anchor_income_diamonds(101, 5000) == 50
    assert calc_anchor_income_diamonds(101, 5250) == 53


def test_calc_anchor_income_clamps_invalid_bounds() -> None:
    assert calc_anchor_income_diamonds(100, -1) == 0
    assert calc_anchor_income_diamonds(100, 10001) == 100
    assert calc_anchor_income_diamonds(-100, 5000) == 0


@pytest.mark.asyncio
async def test_get_anchor_share_bps_falls_back_and_clamps(monkeypatch: pytest.MonkeyPatch) -> None:
    values = iter(["bad", "-1", "10001", "7000"])

    async def fake_get_value(_key: str, _default: str) -> str:
        return next(values)

    monkeypatch.setattr(call_income_service.SystemConfig, "get_value", fake_get_value)

    assert await get_anchor_share_bps() == DEFAULT_ANCHOR_SHARE_BPS
    assert await get_anchor_share_bps() == 0
    assert await get_anchor_share_bps() == 10000
    assert await get_anchor_share_bps() == 7000


def test_resolve_income_anchor_id_only_returns_non_payer_anchor() -> None:
    user = SimpleNamespace(id=1001, is_anchor=False)
    anchor = SimpleNamespace(id=2002, is_anchor=True)

    assert resolve_income_anchor_id([user, anchor], payer_id=1001) == 2002
    assert resolve_income_anchor_id([user, anchor], payer_id=2002) == 0
    assert resolve_income_anchor_id([user], payer_id=1001) == 0


def test_snapshot_share_bps_falls_back_for_dirty_value() -> None:
    assert (
        call_income_service._resolve_snapshot_share_bps(  # noqa: SLF001
            SimpleNamespace(anchor_share_bps="bad")
        )
        == DEFAULT_ANCHOR_SHARE_BPS
    )
    assert (
        call_income_service._resolve_snapshot_share_bps(  # noqa: SLF001
            SimpleNamespace(anchor_share_bps="-1")
        )
        == 0
    )
    assert (
        call_income_service._resolve_snapshot_share_bps(  # noqa: SLF001
            SimpleNamespace(anchor_share_bps="10001")
        )
        == 10000
    )
