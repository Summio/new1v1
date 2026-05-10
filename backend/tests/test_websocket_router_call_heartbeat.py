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
    process_billing = AsyncMock(
        return_value=SimpleNamespace(
            ended_records=[],
            charged_payer_ids=[],
            certified_user_balance_pushes=[],
        )
    )
    router.process_ongoing_call_billing_once = process_billing  # type: ignore[attr-defined]

    result = await router._handle_call_heartbeat_message(  # type: ignore[attr-defined]
        user_id=1,
        msg={"call_id": 7},
    )

    assert result.ok is True
    assert result.end_event is None
    update_last_seen.assert_awaited()
    process_billing.assert_awaited_once_with(call_id=7)


@pytest.mark.asyncio
async def test_call_heartbeat_checks_low_balance_for_payer() -> None:
    from app.websocket import router

    router.CallRecord = SimpleNamespace(  # type: ignore[assignment]
        filter=lambda **_: SimpleNamespace(
            first=AsyncMock(
                return_value=SimpleNamespace(
                    id=7,
                    caller_id=1,
                    callee_id=2,
                    status="ongoing",
                    payer_user_id=1,
                )
            )
        )
    )
    router.update_last_seen = AsyncMock()  # type: ignore[assignment]
    router.process_ongoing_call_billing_once = AsyncMock(  # type: ignore[attr-defined]
        return_value=SimpleNamespace(
            ended_records=[],
            charged_payer_ids=[],
            certified_user_balance_pushes=[],
        )
    )
    check_low_balance = AsyncMock()
    router.maybe_push_call_balance_low_for_user = check_low_balance  # type: ignore[attr-defined]

    result = await router._handle_call_heartbeat_message(  # type: ignore[attr-defined]
        user_id=1,
        msg={"call_id": 7},
    )

    assert result.ok is True
    check_low_balance.assert_awaited_once_with(user_id=1, source="call_heartbeat")


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

    result = await router._handle_call_heartbeat_message(  # type: ignore[attr-defined]
        user_id=3,
        msg={"call_id": 8},
    )

    assert result.ok is False
    assert result.end_event is None
    update_last_seen.assert_not_awaited()


@pytest.mark.asyncio
async def test_call_heartbeat_returns_end_event_for_ended_participant_call() -> None:
    from app.websocket import router

    router.CallRecord = SimpleNamespace(  # type: ignore[assignment]
        filter=lambda **_: SimpleNamespace(
            first=AsyncMock(
                return_value=SimpleNamespace(
                    id=9,
                    caller_id=1,
                    callee_id=2,
                    status="ended",
                    end_reason="balance_empty",
                )
            )
        )
    )
    update_last_seen = AsyncMock()
    router.update_last_seen = update_last_seen  # type: ignore[assignment]

    result = await router._handle_call_heartbeat_message(  # type: ignore[attr-defined]
        user_id=1,
        msg={"call_id": 9},
    )

    assert result.ok is False
    assert result.end_event == {
        "event": "call_ended",
        "data": {"call_id": 9, "end_reason": "balance_empty"},
    }
    update_last_seen.assert_not_awaited()


@pytest.mark.asyncio
async def test_call_heartbeat_returns_end_event_when_billing_closes_call() -> None:
    from app.websocket import router

    call_record = SimpleNamespace(
        id=10,
        caller_id=1,
        callee_id=2,
        status="ongoing",
        end_reason=None,
    )
    ended_record = SimpleNamespace(
        id=10,
        caller_id=1,
        callee_id=2,
        status="ended",
        end_reason="balance_empty",
    )
    router.CallRecord = SimpleNamespace(  # type: ignore[assignment]
        filter=lambda **_: SimpleNamespace(first=AsyncMock(return_value=call_record))
    )
    update_last_seen = AsyncMock()
    router.update_last_seen = update_last_seen  # type: ignore[assignment]
    process_billing = AsyncMock(
        return_value=SimpleNamespace(
            ended_records=[ended_record],
            charged_payer_ids=[],
            certified_user_balance_pushes=[],
        )
    )
    router.process_ongoing_call_billing_once = process_billing  # type: ignore[attr-defined]

    result = await router._handle_call_heartbeat_message(  # type: ignore[attr-defined]
        user_id=1,
        msg={"call_id": 10},
    )

    assert result.ok is False
    assert result.end_event == {
        "event": "call_ended",
        "data": {"call_id": 10, "end_reason": "balance_empty"},
    }
    update_last_seen.assert_awaited()
    process_billing.assert_awaited_once_with(call_id=10)
