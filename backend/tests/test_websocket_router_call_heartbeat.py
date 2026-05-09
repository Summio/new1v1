from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest


@pytest.mark.asyncio
async def test_call_heartbeat_updates_last_seen_for_participant() -> None:
    from app.websocket import router

    router.CallRecord = SimpleNamespace(  # type: ignore[assignment]
        filter=lambda **_: SimpleNamespace(
            first=AsyncMock(return_value=SimpleNamespace(id=7, caller_id=1, callee_id=2, status="ongoing"))
        )
    )
    update_last_seen = AsyncMock()
    router.update_last_seen = update_last_seen  # type: ignore[assignment]

    ok = await router._handle_call_heartbeat_message(  # type: ignore[attr-defined]
        user_id=1,
        msg={"call_id": 7},
    )

    assert ok is True
    update_last_seen.assert_awaited()


@pytest.mark.asyncio
async def test_call_heartbeat_rejects_non_participant() -> None:
    from app.websocket import router

    router.CallRecord = SimpleNamespace(  # type: ignore[assignment]
        filter=lambda **_: SimpleNamespace(
            first=AsyncMock(return_value=SimpleNamespace(id=8, caller_id=10, callee_id=20, status="ongoing"))
        )
    )
    update_last_seen = AsyncMock()
    router.update_last_seen = update_last_seen  # type: ignore[assignment]

    ok = await router._handle_call_heartbeat_message(  # type: ignore[attr-defined]
        user_id=3,
        msg={"call_id": 8},
    )

    assert ok is False
    update_last_seen.assert_not_awaited()
