from datetime import timedelta

from app.core.call_watchdog import _calc_due_minutes, _resolve_force_exit_decision
from app.core.time_utils import now_local_naive


def test_force_exit_uses_last_seen_as_effective_end() -> None:
    connected_at = now_local_naive() - timedelta(seconds=90)
    now_ms = int(now_local_naive().timestamp() * 1000)
    last_seen_ms = now_ms - 9_000
    snapshot = {
        "caller_last_seen_ms": last_seen_ms,
        "callee_last_seen_ms": now_ms - 1_000,
        "caller_left_candidate_ms": now_ms - 8_000,
        "callee_left_candidate_ms": None,
    }

    decision = _resolve_force_exit_decision(
        call_id=1,
        connected_at=connected_at,
        caller_id=11,
        callee_id=22,
        snapshot=snapshot,
        now_ms=now_ms,
        offline_detect_seconds=3,
        settle_grace_seconds=5,
    )

    assert decision.should_end is True
    assert decision.end_reason == "force_exit"
    assert decision.force_exit_user_id == 11
    assert decision.effective_ended_at_ms == last_seen_ms


def test_force_exit_late_detection_not_overcharge() -> None:
    connected_at = now_local_naive() - timedelta(seconds=130)
    now_ms = int(now_local_naive().timestamp() * 1000)
    last_seen_ms = now_ms - 31_000
    snapshot = {
        "caller_last_seen_ms": last_seen_ms,
        "callee_last_seen_ms": now_ms - 1_000,
        "caller_left_candidate_ms": now_ms - 30_000,
        "callee_left_candidate_ms": None,
    }
    decision = _resolve_force_exit_decision(
        call_id=9,
        connected_at=connected_at,
        caller_id=1,
        callee_id=2,
        snapshot=snapshot,
        now_ms=now_ms,
        offline_detect_seconds=3,
        settle_grace_seconds=5,
    )
    duration_by_last_seen = max(
        0,
        int((last_seen_ms - int(connected_at.timestamp() * 1000)) / 1000),
    )
    # 按有效结束时间点计费，不按 watchdog 检测时间点计费
    assert _calc_due_minutes(duration_by_last_seen, 10) <= _calc_due_minutes(130, 10)
    assert decision.should_end is True
