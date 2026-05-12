import json
from datetime import datetime
from types import SimpleNamespace

import pytest

from app.api.v1.notification.notification import _dump_task
from app.schemas.system_notification import SystemNotificationTaskCreateIn
from app.services.system_notification_service import (
    NotificationValidationError,
    _dump_user_notification,
    build_business_notification_key,
    build_run_key,
    calculate_next_run_at,
    ensure_repeat_has_end_condition,
    format_notification_datetime,
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


def test_validate_task_payload_rejects_removed_target_filters() -> None:
    base = {
        "title": "维护通知",
        "summary": "今晚服务维护",
        "content": "今晚 23:00 开始维护。",
        "type": "announcement",
        "send_mode": "immediate",
        "status": "scheduled",
        "target_mode": "filter",
    }

    with pytest.raises(NotificationValidationError, match="不支持的筛选条件"):
        validate_task_payload({**base, "target_filters": {"certification_status": "approved"}})

    with pytest.raises(NotificationValidationError, match="不支持的筛选条件"):
        validate_task_payload({**base, "target_filters": {"status": "normal"}})


def test_validate_task_payload_accepts_online_target_filter() -> None:
    payload = validate_task_payload(
        {
            "title": "维护通知",
            "summary": "今晚服务维护",
            "content": "今晚 23:00 开始维护。",
            "type": "announcement",
            "send_mode": "immediate",
            "status": "scheduled",
            "target_mode": "filter",
            "target_filters": {"is_online": True},
        }
    )

    assert payload["target_filters"] == {"is_online": True}


def test_validate_task_payload_accepts_admin_schema_enum_dump() -> None:
    req = SystemNotificationTaskCreateIn(
        title="维护通知",
        summary="今晚服务维护",
        content="今晚 23:00 开始维护。\n预计 30 分钟。",
        type="announcement",
        send_mode="immediate",
        status="scheduled",
        target_mode="all",
    )

    payload = validate_task_payload(req.model_dump())

    assert payload["type"] == "announcement"
    assert payload["send_mode"] == "immediate"
    assert payload["status"] == "scheduled"
    assert payload["target_mode"] == "all"


def test_notification_datetime_formatter_returns_json_safe_text() -> None:
    assert format_notification_datetime(datetime(2026, 5, 12, 18, 0, 1)) == "2026-05-12T18:00:01"
    assert format_notification_datetime(None) is None


def test_app_notification_dump_is_json_serializable() -> None:
    notification = SimpleNamespace(
        id=12,
        title="提现结果通知",
        summary="你的提现申请已通过",
        type="account",
        published_at=datetime(2026, 5, 12, 18, 0),
        publish_at=datetime(2026, 5, 12, 18, 0),
        content="你的提现申请已通过。\n请注意查收。",
    )
    receipt = SimpleNamespace(read_at=datetime(2026, 5, 12, 18, 5))

    data = _dump_user_notification(notification, receipt, include_content=True)

    json.dumps(data)
    assert data["publish_at"] == "2026-05-12T18:00:00"
    assert data["read_at"] == "2026-05-12T18:05:00"


@pytest.mark.asyncio
async def test_admin_task_dump_is_json_serializable(monkeypatch: pytest.MonkeyPatch) -> None:
    async def fake_estimate_target_count(**_: object) -> int:
        return 8

    monkeypatch.setattr("app.api.v1.notification.notification.estimate_target_count", fake_estimate_target_count)
    task = SimpleNamespace(
        id=3,
        title="维护通知",
        summary="今晚服务维护",
        content="今晚 23:00 开始维护。",
        type="announcement",
        status="scheduled",
        send_mode="once",
        target_mode="all",
        target_user_ids=[],
        target_filters={},
        publish_at=datetime(2026, 5, 12, 18, 0),
        repeat_type=None,
        repeat_time=None,
        repeat_weekday=None,
        repeat_month_day=None,
        start_at=None,
        end_at=datetime(2026, 5, 31, 23, 59),
        max_runs=None,
        run_count=0,
        next_run_at=datetime(2026, 5, 12, 18, 0),
        last_run_at=None,
        created_at=datetime(2026, 5, 12, 17, 0),
        updated_at=datetime(2026, 5, 12, 17, 30),
    )

    data = await _dump_task(task)

    json.dumps(data)
    assert data["publish_at"] == "2026-05-12T18:00:00"
    assert data["next_run_at"] == "2026-05-12T18:00:00"
    assert data["created_at"] == "2026-05-12T17:00:00"
    assert data["estimated_count"] == 8
