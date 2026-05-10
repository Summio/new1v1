from pathlib import Path

import pytest

BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent
CALL_API = BACKEND_ROOT / "app/api/v1/app/call.py"
WATCHDOG = BACKEND_ROOT / "app/core/call_watchdog.py"
WS_EVENTS = BACKEND_ROOT / "app/websocket/events.py"
WS_ROUTER = BACKEND_ROOT / "app/websocket/router.py"
API_ENDPOINTS = REPO_ROOT / "huanxi/lib/core/constants/api_endpoints.dart"
CALL_OUTGOING_PAGE = REPO_ROOT / "huanxi/lib/modules/call/call_outgoing_page.dart"
CALL_ROOM_PAGE = REPO_ROOT / "huanxi/lib/modules/call/call_room_page.dart"
CALL_WS_CONTROLLER = REPO_ROOT / "huanxi/lib/modules/call/controllers/call_ws_controller.dart"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_watchdog_force_exit_time_uses_project_timezone_helpers() -> None:
    source = _read(WATCHDOG)

    assert "to_utc_aware(connected_at).timestamp()" in source
    assert "to_local_naive_for_db(datetime.fromtimestamp(ms / 1000, timezone.utc))" in source


def test_accept_call_closes_pending_record_when_resolved_payer_balance_is_insufficient() -> None:
    source = _read(CALL_API)
    accept_source = source.split("async def accept_call(req_in: CallActionIn):", 1)[1].split(
        "async def reject_call(req_in: CallActionIn):",
        1,
    )[0]
    insufficient_branch = accept_source.split('return Fail(code=501, msg="余额不足，请先充值")', 1)[0]

    assert 'call_record.status = "ended"' in insufficient_branch
    assert 'call_record.end_reason = "balance_empty"' in insufficient_branch
    assert 'call_record.end_basis = "balance_empty"' in insufficient_branch
    assert "_ws_push_call_balance_empty" in insufficient_branch


def test_call_accepted_is_pushed_as_critical_event() -> None:
    source = _read(WS_EVENTS)
    accepted_source = source.split("async def push_call_accepted", 1)[1].split(
        "async def push_call_rejected",
        1,
    )[0]

    assert '"call_accepted"' in accepted_source
    assert "critical=True" in accepted_source


@pytest.mark.asyncio
async def test_call_heartbeat_broadcasts_end_event_when_billing_closes_call(monkeypatch: pytest.MonkeyPatch) -> None:
    from types import SimpleNamespace
    from unittest.mock import AsyncMock

    from app.websocket import router

    call_record = SimpleNamespace(id=10, caller_id=1, callee_id=2, status="ongoing", end_reason=None)
    ended_record = SimpleNamespace(id=10, caller_id=1, callee_id=2, status="ended", end_reason="balance_empty")
    router.CallRecord = SimpleNamespace(  # type: ignore[assignment]
        filter=lambda **_: SimpleNamespace(first=AsyncMock(return_value=call_record))
    )
    monkeypatch.setattr(router, "update_last_seen", AsyncMock())
    monkeypatch.setattr(
        router,
        "process_ongoing_call_billing_once",
        AsyncMock(
            return_value=SimpleNamespace(
                ended_records=[ended_record],
                charged_payer_ids=[],
                certified_user_balance_pushes=[],
            )
        ),
    )
    push_balance_empty = AsyncMock()
    monkeypatch.setattr(router.ws_events, "push_call_balance_empty", push_balance_empty)

    result = await router._handle_call_heartbeat_message(user_id=1, msg={"call_id": 10})  # type: ignore[attr-defined]

    assert result.end_event == {
        "event": "call_ended",
        "data": {"call_id": 10, "end_reason": "balance_empty"},
    }
    push_balance_empty.assert_awaited_once_with(caller_id=1, callee_id=2, call_id=10)


def test_call_status_polling_route_stays_removed() -> None:
    assert "class CallStatusOut" not in _read(BACKEND_ROOT / "app/schemas/app_api.py")
    assert '@router.get("/call/status"' not in _read(CALL_API)
    assert "static const String callStatus = 'app/call/status';" not in _read(API_ENDPOINTS)


def test_outgoing_page_polls_call_status_as_call_accepted_fallback() -> None:
    source = _read(CALL_OUTGOING_PAGE)

    assert "Timer? _rtcJoinPollTimer;" in source
    assert "_startRtcJoinPolling()" in source
    assert "ApiEndpoints.rtcToken" in source
    assert "_rtcJoinPollTimer?.cancel();" in source


def test_room_local_failure_paths_notify_end_api_when_backend_may_still_be_ongoing() -> None:
    room_source = _read(CALL_ROOM_PAGE)
    ws_source = _read(CALL_WS_CONTROLLER)

    remote_end_branch = room_source.split("onRemoteEnd: (endReason)", 1)[1].split("onLog: _log", 1)[0]
    assert "beginEnding(" in remote_end_branch
    assert "endReason: endReason" in remote_end_branch
    assert "notifyEndApi: true" in remote_end_branch
    assert "beginEnding(endReason: 'timeout', notifyEndApi: true)" in room_source
    network_lost_branch = ws_source.split("endReason: 'network_lost'", 1)[1].split(");", 1)[0]
    assert "notifyEndApi: true" in network_lost_branch
