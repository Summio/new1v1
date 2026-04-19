from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest


@pytest.mark.asyncio
async def test_update_and_get_snapshot() -> None:
    from app.core import call_presence

    redis = SimpleNamespace(
        hset=AsyncMock(),
        expire=AsyncMock(),
        hgetall=AsyncMock(
            return_value={
                "caller_last_seen_ms": "1700000000000",
                "callee_last_seen_ms": "1700000000100",
            }
        ),
    )

    call_presence.get_redis = AsyncMock(return_value=redis)  # type: ignore[assignment]

    await call_presence.update_last_seen(
        call_id=1,
        user_id=100,
        role="caller",
        now_ms=1700000000000,
    )
    snap = await call_presence.get_snapshot(call_id=1)
    assert snap["caller_last_seen_ms"] == 1700000000000
    assert snap["callee_last_seen_ms"] == 1700000000100


@pytest.mark.asyncio
async def test_mark_and_clear_left_candidate() -> None:
    from app.core import call_presence

    redis = SimpleNamespace(
        hset=AsyncMock(),
        hdel=AsyncMock(),
        expire=AsyncMock(),
        hgetall=AsyncMock(
            return_value={
                "caller_left_candidate_ms": "1700000000200",
            }
        ),
    )
    call_presence.get_redis = AsyncMock(return_value=redis)  # type: ignore[assignment]

    await call_presence.mark_left_candidate(
        call_id=2,
        role="caller",
        now_ms=1700000000200,
    )
    snap = await call_presence.get_snapshot(call_id=2)
    assert snap["caller_left_candidate_ms"] == 1700000000200

    await call_presence.clear_left_candidate(call_id=2, role="caller")
    redis.hdel.assert_awaited()
