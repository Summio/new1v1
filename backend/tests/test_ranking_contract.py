import sys
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace

import pytest

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.services import ranking_service  # noqa: E402
from app.services.ranking_service import (  # noqa: E402
    BOARD_CHARM,
    BOARD_INVITE,
    BOARD_WEALTH,
    build_app_ranking_rows,
    clamp_app_display_limit,
    format_score_value,
    get_period_window,
)


def test_ranking_period_window_uses_natural_beijing_day_week_month() -> None:
    now = datetime(2026, 5, 8, 15, 30, 0)

    day_start, day_end = get_period_window("day", now=now)
    assert day_start == datetime(2026, 5, 8, 0, 0, 0)
    assert day_end == datetime(2026, 5, 9, 0, 0, 0)

    week_start, week_end = get_period_window("week", now=now)
    assert week_start == datetime(2026, 5, 4, 0, 0, 0)
    assert week_end == datetime(2026, 5, 11, 0, 0, 0)

    month_start, month_end = get_period_window("month", now=now)
    assert month_start == datetime(2026, 5, 1, 0, 0, 0)
    assert month_end == datetime(2026, 6, 1, 0, 0, 0)


def test_ranking_app_display_limit_defaults_and_clamps() -> None:
    assert clamp_app_display_limit(None) == 20
    assert clamp_app_display_limit("") == 20
    assert clamp_app_display_limit("bad") == 20
    assert clamp_app_display_limit("0") == 20
    assert clamp_app_display_limit("5") == 5
    assert clamp_app_display_limit("101") == 20


def test_ranking_score_format_removes_useless_decimals() -> None:
    assert format_score_value(Decimal("120.00")) == "120"
    assert format_score_value(Decimal("120.50")) == "120.5"
    assert format_score_value(Decimal("120.57")) == "120.57"


def test_app_ranking_rows_hide_real_score_and_show_gap_from_top() -> None:
    rows = [
        {
            "rank": 1,
            "user_id": 10,
            "nickname": "第一名",
            "avatar": "/a.png",
            "score": Decimal("100.00"),
            "is_certified_user": True,
        },
        {
            "rank": 2,
            "user_id": 11,
            "nickname": "第二名",
            "avatar": "/b.png",
            "score": Decimal("76.50"),
            "is_certified_user": False,
        },
    ]

    app_rows = build_app_ranking_rows(rows, board=BOARD_CHARM)

    assert "score" not in app_rows[0]
    assert app_rows[0]["score_gap_from_top"] == 0.0
    assert app_rows[0]["score_gap_text"] == "距榜首 0 钻石"
    assert app_rows[1]["score_gap_from_top"] == 23.5
    assert app_rows[1]["score_gap_text"] == "距榜首 23.5 钻石"


def test_ranking_board_units_are_stable() -> None:
    assert build_app_ranking_rows([], board=BOARD_CHARM) == []
    assert build_app_ranking_rows([], board=BOARD_WEALTH) == []
    assert build_app_ranking_rows([], board=BOARD_INVITE) == []


def test_snapshot_stale_check_accepts_aware_db_timestamp(monkeypatch: pytest.MonkeyPatch) -> None:
    now = datetime(2026, 5, 8, 12, 0, 0)
    computed_at = (now - timedelta(seconds=30)).replace(tzinfo=timezone(timedelta(hours=8)))

    monkeypatch.setattr(ranking_service, "now_local_naive", lambda: now)

    assert ranking_service._is_snapshot_stale(computed_at) is False


@pytest.mark.asyncio
async def test_wait_for_existing_snapshot_returns_concurrent_refresh_result(monkeypatch: pytest.MonkeyPatch) -> None:
    period_start = datetime(2026, 5, 8, 0, 0, 0)
    period_end = datetime(2026, 5, 9, 0, 0, 0)
    computed_at = datetime(2026, 5, 8, 12, 0, 0)
    calls = 0

    async def fake_latest_snapshot_meta(board: str, period: str, start: datetime):
        nonlocal calls
        calls += 1
        if calls == 1:
            return None
        return SimpleNamespace(board=board, period=period, computed_at=computed_at)

    async def fake_sleep(_seconds: float) -> None:
        return None

    monkeypatch.setattr(ranking_service, "_latest_snapshot_meta", fake_latest_snapshot_meta)
    monkeypatch.setattr(ranking_service.asyncio, "sleep", fake_sleep)

    meta = await ranking_service.wait_for_existing_snapshot(
        BOARD_CHARM,
        "day",
        period_start,
        period_end,
        attempts=2,
        delay_seconds=0.01,
    )

    assert meta is not None
    assert meta["board"] == BOARD_CHARM
    assert meta["period"] == "day"
    assert meta["period_start"] == period_start
    assert meta["period_end"] == period_end
    assert meta["computed_at"] == computed_at
    assert calls == 2


@pytest.mark.asyncio
async def test_refresh_reads_existing_snapshot_when_redis_unavailable(monkeypatch: pytest.MonkeyPatch) -> None:
    period_start = datetime(2026, 5, 8, 0, 0, 0)
    period_end = datetime(2026, 5, 9, 0, 0, 0)
    computed_at = datetime(2000, 1, 1, 0, 0, 0)

    async def fake_get_redis():
        raise RuntimeError("redis unavailable")

    async def fake_latest_snapshot_meta(board: str, period: str, start: datetime):
        return SimpleNamespace(board=board, period=period, computed_at=computed_at)

    async def fail_aggregate(*_args, **_kwargs):
        raise AssertionError("should not aggregate when redis is unavailable and snapshot exists")

    monkeypatch.setattr(ranking_service, "get_redis", fake_get_redis)
    monkeypatch.setattr(ranking_service, "get_period_window", lambda _period: (period_start, period_end))
    monkeypatch.setattr(ranking_service, "_latest_snapshot_meta", fake_latest_snapshot_meta)
    monkeypatch.setattr(ranking_service, "aggregate_board_scores", fail_aggregate)

    meta = await ranking_service.refresh_ranking_snapshot(BOARD_CHARM, "day")

    assert meta["board"] == BOARD_CHARM
    assert meta["period"] == "day"
    assert meta["period_start"] == period_start
    assert meta["period_end"] == period_end
    assert meta["computed_at"] == computed_at
