from datetime import datetime

import pytest

from app.services.system_notification_service import (
    NotificationValidationError,
    build_business_notification_key,
    build_run_key,
    calculate_next_run_at,
    ensure_repeat_has_end_condition,
    normalize_user_ids,
    validate_task_payload,
)


def test_repeat_notification_requires_end_at_or_max_runs() -> None:
    with pytest.raises(NotificationValidationError):
        ensure_repeat_has_end_condition(send_mode="repeat", end_at=None, max_runs=None)

    ensure_repeat_has_end_condition(send_mode="repeat", end_at=datetime(2026, 5, 31, 23, 59), max_runs=None)
    ensure_repeat_has_end_condition(send_mode="repeat", end_at=None, max_runs=3)
    ensure_repeat_has_end_condition(send_mode="once", end_at=None, max_runs=None)


def test_calculate_next_run_at_supports_daily_weekly_and_monthly() -> None:
    current = datetime(2026, 5, 12, 10, 0)

    assert calculate_next_run_at(
        repeat_type="daily",
        after=current,
        repeat_time="09:30",
    ) == datetime(2026, 5, 13, 9, 30)
    assert calculate_next_run_at(
        repeat_type="daily",
        after=current,
        repeat_time="11:30",
    ) == datetime(2026, 5, 12, 11, 30)
    assert calculate_next_run_at(
        repeat_type="weekly",
        after=current,
        repeat_time="18:00",
        repeat_weekday=4,
    ) == datetime(2026, 5, 15, 18, 0)
    assert calculate_next_run_at(
        repeat_type="monthly",
        after=datetime(2026, 2, 28, 12, 0),
        repeat_time="08:00",
        repeat_month_day=31,
    ) == datetime(2026, 3, 31, 8, 0)


def test_run_and_business_keys_are_stable() -> None:
    scheduled = datetime(2026, 5, 12, 18, 0)

    assert build_run_key(task_id=8, scheduled_run_at=scheduled) == "task:8:2026-05-12T18:00:00"
    assert build_business_notification_key("follow", 12, 34) == "follow:12:34"


def test_normalize_user_ids_accepts_strings_and_lists() -> None:
    assert normalize_user_ids("1, 2,3") == [1, 2, 3]
    assert normalize_user_ids([3, "2", "3", 1]) == [1, 2, 3]

    with pytest.raises(NotificationValidationError):
        normalize_user_ids("1,abc")


def test_validate_task_payload_requires_once_publish_at_before_activation() -> None:
    with pytest.raises(NotificationValidationError, match="一次性定时必须选择发布时间"):
        validate_task_payload(
            {
                "title": "提现结果通知",
                "summary": "你的提现申请已通过",
                "content": "你的提现申请已通过。\n请注意查收。",
                "type": "account",
                "send_mode": "once",
                "status": "scheduled",
                "target_mode": "all",
            }
        )


def test_validate_task_payload_preserves_plain_text_newlines() -> None:
    payload = validate_task_payload(
        {
            "title": "维护通知",
            "summary": "今晚服务维护",
            "content": "今晚 23:00 开始维护。\n预计 30 分钟。",
            "type": "announcement",
            "send_mode": "immediate",
            "status": "scheduled",
            "target_mode": "all",
        }
    )

    assert payload["content"] == "今晚 23:00 开始维护。\n预计 30 分钟。"
