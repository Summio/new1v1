import json
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from app.api.v1.notification.notification import _dump_task
from app.schemas.system_notification import SystemNotificationTaskCreateIn
from app.services import system_notification_service
from app.services.system_notification_service import (
    MAX_NOTIFICATION_TARGET_USERS,
    RECEIPT_BULK_CREATE_BATCH_SIZE,
    NotificationValidationError,
    _notification_due_occurrences,
    _dump_user_notification,
    build_business_notification_key,
    build_run_key,
    calculate_next_run_at,
    ensure_repeat_has_end_condition,
    format_notification_datetime,
    normalize_user_ids,
    publish_due_task,
    publish_task_once,
    validate_task_payload,
)


class _AwaitableQuery:
    def __init__(self, items=None, first_value=None, exists_value=None, count_value=None):
        self.items = list(items or [])
        self.first_value = first_value
        self.exists_value = exists_value
        self.count_value = count_value
        self.offset_value = 0
        self.limit_value = None

    def order_by(self, *args):
        return self

    def offset(self, value):
        self.offset_value = value
        return self

    def limit(self, value):
        self.limit_value = value
        return self

    async def first(self):
        if self.first_value is not None:
            return self.first_value
        return self.items[0] if self.items else None

    async def exists(self):
        return bool(self.exists_value)

    async def count(self):
        if self.count_value is not None:
            return self.count_value
        return len(self.items)

    async def all(self):
        end = None if self.limit_value is None else self.offset_value + self.limit_value
        return self.items[self.offset_value:end]

    def __await__(self):
        async def _result():
            end = None if self.limit_value is None else self.offset_value + self.limit_value
            return self.items[self.offset_value:end]

        return _result().__await__()


class _FakeTransaction:
    async def __aenter__(self):
        return None

    async def __aexit__(self, *_):
        return None


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
            "content": "今晚 23:00 开始维护。\n预计 30 分钟。",
            "type": "announcement",
            "send_mode": "immediate",
            "status": "scheduled",
            "target_mode": "all",
        }
    )

    assert payload["content"] == "今晚 23:00 开始维护。\n预计 30 分钟。"
    assert "title" not in payload
    assert "summary" not in payload


def test_validate_task_payload_rejects_empty_content() -> None:
    with pytest.raises(NotificationValidationError, match="正文不能为空"):
        validate_task_payload(
            {
                "content": "  ",
                "type": "announcement",
                "send_mode": "immediate",
                "status": "scheduled",
                "target_mode": "all",
            }
        )


def test_validate_task_payload_rejects_removed_target_filters() -> None:
    base = {
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
    assert "title" not in payload
    assert "summary" not in payload


def test_notification_datetime_formatter_returns_json_safe_text() -> None:
    assert format_notification_datetime(datetime(2026, 5, 12, 18, 0, 1)) == "2026-05-12T18:00:01"
    assert format_notification_datetime(None) is None


def test_app_notification_dump_is_json_serializable() -> None:
    notification = SimpleNamespace(
        id=12,
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
    assert data["content"] == "你的提现申请已通过。\n请注意查收。"
    assert "title" not in data
    assert "summary" not in data


@pytest.mark.asyncio
async def test_admin_task_dump_is_json_serializable(monkeypatch: pytest.MonkeyPatch) -> None:
    async def fake_estimate_target_count(**_: object) -> int:
        return 8

    monkeypatch.setattr("app.api.v1.notification.notification.estimate_target_count", fake_estimate_target_count)
    task = SimpleNamespace(
        id=3,
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
    assert data["content"] == "今晚 23:00 开始维护。"
    assert "title" not in data
    assert "summary" not in data


@pytest.mark.asyncio
async def test_admin_task_dump_normalizes_legacy_enum_text(monkeypatch: pytest.MonkeyPatch) -> None:
    async def fake_estimate_target_count(**_: object) -> int:
        return 8

    monkeypatch.setattr("app.api.v1.notification.notification.estimate_target_count", fake_estimate_target_count)
    task = SimpleNamespace(
        id=3,
        content="今晚 23:00 开始维护。",
        type="NotificationType.ANNOUNCEMENT",
        status="NotificationTaskStatus.SCHEDULED",
        send_mode="NotificationSendMode.ONCE",
        target_mode="NotificationTargetMode.ALL",
        target_user_ids=[],
        target_filters={},
        publish_at=None,
        repeat_type=None,
        repeat_time=None,
        repeat_weekday=None,
        repeat_month_day=None,
        start_at=None,
        end_at=None,
        max_runs=None,
        run_count=0,
        next_run_at=None,
        last_run_at=None,
        created_at=None,
        updated_at=None,
    )

    data = await _dump_task(task)

    assert data["type"] == "announcement"
    assert data["status"] == "scheduled"
    assert data["send_mode"] == "once"
    assert data["target_mode"] == "all"


def test_notification_due_occurrences_repeat_backfills_recent_30_runs() -> None:
    task = SimpleNamespace(
        id=8,
        status="running",
        send_mode="repeat",
        created_at=datetime(2026, 5, 1, 8, 0),
        publish_at=None,
        repeat_type="daily",
        repeat_time="09:00",
        repeat_weekday=None,
        repeat_month_day=None,
        start_at=datetime(2026, 4, 1, 0, 0),
        end_at=None,
        max_runs=None,
    )

    occurrences = _notification_due_occurrences(task, now=datetime(2026, 5, 17, 10, 0))

    assert len(occurrences) == 30
    assert occurrences[0].scheduled_run_at == datetime(2026, 4, 18, 9, 0)
    assert occurrences[-1].scheduled_run_at == datetime(2026, 5, 17, 9, 0)
    assert len({item.run_key for item in occurrences}) == 30


@pytest.mark.asyncio
async def test_publish_task_once_rejects_target_count_over_limit(monkeypatch: pytest.MonkeyPatch) -> None:
    class FakeNotificationQuery:
        async def first(self) -> None:
            return None

    class FakeNotification:
        @staticmethod
        def filter(**_: object) -> FakeNotificationQuery:
            return FakeNotificationQuery()

        @staticmethod
        async def create(**_: object) -> object:
            raise AssertionError("超过人数上限时不应创建通知")

    async def fake_resolve_target_user_ids(**_: object) -> list[int]:
        return list(range(1, MAX_NOTIFICATION_TARGET_USERS + 2))

    monkeypatch.setattr(system_notification_service, "SystemNotification", FakeNotification)
    monkeypatch.setattr(system_notification_service, "resolve_target_user_ids", fake_resolve_target_user_ids)

    task = SimpleNamespace(
        id=1,
        next_run_at=datetime(2026, 5, 12, 18, 0),
        publish_at=None,
        target_mode="all",
        target_user_ids=[],
        target_filters={},
        content="上线维护通知",
        type="announcement",
    )

    with pytest.raises(NotificationValidationError, match="单次通知最多支持 5000 人"):
        await publish_task_once(task)


@pytest.mark.asyncio
async def test_publish_task_once_bulk_creates_receipts_without_websocket_push(monkeypatch: pytest.MonkeyPatch) -> None:
    target_user_ids = list(range(1, MAX_NOTIFICATION_TARGET_USERS + 1))
    batch_sizes: list[int] = []

    class FakeTransaction:
        async def __aenter__(self) -> None:
            return None

        async def __aexit__(self, *_: object) -> None:
            return None

    class FakeNotificationQuery:
        async def first(self) -> None:
            return None

    class FakeNotification:
        id = 99

        @staticmethod
        def filter(**_: object) -> FakeNotificationQuery:
            return FakeNotificationQuery()

        @staticmethod
        async def create(**_: object) -> "FakeNotification":
            return FakeNotification()

    class FakeReceipt:
        def __init__(self, **kwargs: object) -> None:
            self.kwargs = kwargs

        @staticmethod
        async def bulk_create(receipts: list["FakeReceipt"], ignore_conflicts: bool = False) -> None:
            assert ignore_conflicts is True
            batch_sizes.append(len(receipts))

    async def fake_resolve_target_user_ids(**_: object) -> list[int]:
        return target_user_ids

    async def fail_push_unread_changed_for_users(user_ids: list[int]) -> None:
        raise AssertionError("发布系统通知不应再推送未读数变化")

    monkeypatch.setattr(system_notification_service, "SystemNotification", FakeNotification)
    monkeypatch.setattr(system_notification_service, "SystemNotificationReceipt", FakeReceipt)
    monkeypatch.setattr(system_notification_service, "resolve_target_user_ids", fake_resolve_target_user_ids)
    monkeypatch.setattr(system_notification_service, "in_transaction", lambda: FakeTransaction())
    monkeypatch.setattr(
        system_notification_service,
        "_push_unread_changed_for_users",
        fail_push_unread_changed_for_users,
        raising=False,
    )

    task = SimpleNamespace(
        id=1,
        next_run_at=datetime(2026, 5, 12, 18, 0),
        publish_at=None,
        target_mode="all",
        target_user_ids=[],
        target_filters={},
        content="上线维护通知",
        type="announcement",
    )

    notification = await publish_task_once(task)

    assert isinstance(notification, FakeNotification)
    assert batch_sizes == [RECEIPT_BULK_CREATE_BATCH_SIZE] * (
        MAX_NOTIFICATION_TARGET_USERS // RECEIPT_BULK_CREATE_BATCH_SIZE
    )


@pytest.mark.asyncio
async def test_list_user_notifications_materializes_immediate_task_for_target_user(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    now = datetime(2026, 5, 17, 10, 0)
    task = SimpleNamespace(
        id=8,
        status="running",
        send_mode="immediate",
        created_at=datetime(2026, 5, 17, 9, 30),
        publish_at=None,
        repeat_type=None,
        repeat_time=None,
        repeat_weekday=None,
        repeat_month_day=None,
        start_at=None,
        end_at=None,
        max_runs=None,
        target_mode="all",
        target_user_ids=[],
        target_filters=None,
        content="维护通知",
        type="announcement",
    )
    notifications = []
    receipts = []
    notification_id = {"next": 1}

    class FakeTask:
        @classmethod
        def filter(cls, **kwargs):
            assert kwargs == {"status": "running", "send_mode__in": ["immediate", "once", "repeat"]}
            return _AwaitableQuery([task])

    class FakeNotification:
        @classmethod
        def filter(cls, **kwargs):
            if "run_key" in kwargs:
                return _AwaitableQuery([item for item in notifications if item.run_key == kwargs["run_key"]])
            if "id__in" in kwargs:
                ids = {int(item) for item in kwargs["id__in"]}
                return _AwaitableQuery([item for item in notifications if int(item.id) in ids])
            return _AwaitableQuery()

        @classmethod
        async def create(cls, **kwargs):
            item = SimpleNamespace(id=notification_id["next"], **kwargs)
            notification_id["next"] += 1
            notifications.append(item)
            return item

    class FakeReceipt:
        def __init__(self, **kwargs):
            self.id = len(receipts) + 1
            self.notification_id = kwargs["notification_id"]
            self.user_id = kwargs["user_id"]
            self.read_at = kwargs.get("read_at")
            self.created_at = now

        @classmethod
        def filter(cls, **kwargs):
            rows = receipts
            if "user_id" in kwargs:
                rows = [item for item in rows if item.user_id == kwargs["user_id"]]
            if "notification_id" in kwargs:
                rows = [item for item in rows if item.notification_id == kwargs["notification_id"]]
            return _AwaitableQuery(rows, count_value=len(rows))

        @classmethod
        async def get_or_create(cls, **kwargs):
            for item in receipts:
                if item.notification_id == kwargs["notification_id"] and item.user_id == kwargs["user_id"]:
                    return item, False
            item = cls(**kwargs)
            receipts.append(item)
            return item, True

    monkeypatch.setattr(system_notification_service, "SystemNotificationTask", FakeTask)
    monkeypatch.setattr(system_notification_service, "SystemNotification", FakeNotification)
    monkeypatch.setattr(system_notification_service, "SystemNotificationReceipt", FakeReceipt)
    monkeypatch.setattr(system_notification_service, "in_transaction", lambda: _FakeTransaction())
    monkeypatch.setattr(system_notification_service, "now_local_naive", lambda: now)

    rows, total = await system_notification_service.list_user_notifications(user_id=34, page=1, page_size=20)
    rows_again, total_again = await system_notification_service.list_user_notifications(user_id=34, page=1, page_size=20)

    assert total == 1
    assert total_again == 1
    assert [row["content"] for row in rows] == ["维护通知"]
    assert [row["id"] for row in rows_again] == [1]
    assert len(notifications) == 1
    assert len(receipts) == 1


@pytest.mark.asyncio
async def test_list_user_notifications_hides_once_task_before_publish_at(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    now = datetime(2026, 5, 17, 10, 0)
    task = SimpleNamespace(
        id=8,
        status="running",
        send_mode="once",
        created_at=datetime(2026, 5, 17, 9, 30),
        publish_at=datetime(2026, 5, 17, 11, 0),
        repeat_type=None,
        repeat_time=None,
        repeat_weekday=None,
        repeat_month_day=None,
        start_at=None,
        end_at=None,
        max_runs=None,
        target_mode="all",
        target_user_ids=[],
        target_filters=None,
        content="定时通知",
        type="announcement",
    )
    created_notifications = []

    class FakeTask:
        @classmethod
        def filter(cls, **kwargs):
            return _AwaitableQuery([task])

    class FakeNotification:
        @classmethod
        def filter(cls, **kwargs):
            return _AwaitableQuery([])

        @classmethod
        async def create(cls, **kwargs):
            created_notifications.append(kwargs)
            return SimpleNamespace(id=1, **kwargs)

    class FakeReceipt:
        @classmethod
        def filter(cls, **kwargs):
            return _AwaitableQuery([], count_value=0)

        @classmethod
        async def get_or_create(cls, **kwargs):
            raise AssertionError("未到发布时间不应创建 receipt")

    monkeypatch.setattr(system_notification_service, "SystemNotificationTask", FakeTask)
    monkeypatch.setattr(system_notification_service, "SystemNotification", FakeNotification)
    monkeypatch.setattr(system_notification_service, "SystemNotificationReceipt", FakeReceipt)
    monkeypatch.setattr(system_notification_service, "now_local_naive", lambda: now)

    rows, total = await system_notification_service.list_user_notifications(user_id=34, page=1, page_size=20)

    assert rows == []
    assert total == 0
    assert created_notifications == []


@pytest.mark.asyncio
async def test_list_user_notifications_materializes_once_task_after_publish_at(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    now = datetime(2026, 5, 17, 10, 0)
    publish_at = datetime(2026, 5, 17, 9, 0)
    task = SimpleNamespace(
        id=8,
        status="running",
        send_mode="once",
        created_at=datetime(2026, 5, 17, 8, 30),
        publish_at=publish_at,
        repeat_type=None,
        repeat_time=None,
        repeat_weekday=None,
        repeat_month_day=None,
        start_at=None,
        end_at=None,
        max_runs=None,
        target_mode="all",
        target_user_ids=[],
        target_filters=None,
        content="定时通知",
        type="announcement",
    )
    notifications = []
    receipts = []

    class FakeTask:
        @classmethod
        def filter(cls, **kwargs):
            return _AwaitableQuery([task])

    class FakeNotification:
        @classmethod
        def filter(cls, **kwargs):
            if "run_key" in kwargs:
                return _AwaitableQuery([item for item in notifications if item.run_key == kwargs["run_key"]])
            if "id__in" in kwargs:
                return _AwaitableQuery(notifications)
            return _AwaitableQuery()

        @classmethod
        async def create(cls, **kwargs):
            item = SimpleNamespace(id=1, **kwargs)
            notifications.append(item)
            return item

    class FakeReceipt:
        def __init__(self, **kwargs):
            self.notification_id = kwargs["notification_id"]
            self.user_id = kwargs["user_id"]
            self.read_at = None
            self.created_at = now

        @classmethod
        def filter(cls, **kwargs):
            rows = receipts
            if "user_id" in kwargs:
                rows = [item for item in rows if item.user_id == kwargs["user_id"]]
            return _AwaitableQuery(rows, count_value=len(rows))

        @classmethod
        async def get_or_create(cls, **kwargs):
            item = cls(**kwargs)
            receipts.append(item)
            return item, True

    monkeypatch.setattr(system_notification_service, "SystemNotificationTask", FakeTask)
    monkeypatch.setattr(system_notification_service, "SystemNotification", FakeNotification)
    monkeypatch.setattr(system_notification_service, "SystemNotificationReceipt", FakeReceipt)
    monkeypatch.setattr(system_notification_service, "in_transaction", lambda: _FakeTransaction())
    monkeypatch.setattr(system_notification_service, "now_local_naive", lambda: now)

    rows, total = await system_notification_service.list_user_notifications(user_id=34, page=1, page_size=20)

    assert total == 1
    assert rows[0]["content"] == "定时通知"
    assert notifications[0].scheduled_run_at == publish_at
    assert notifications[0].run_key == "task:8:2026-05-17T09:00:00"


@pytest.mark.asyncio
async def test_materialize_due_notifications_does_not_materialize_for_non_target_user(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    task = SimpleNamespace(
        id=8,
        status="running",
        send_mode="immediate",
        created_at=datetime(2026, 5, 17, 9, 30),
        publish_at=None,
        target_mode="user_ids",
        target_user_ids=[99],
        target_filters=None,
        content="定向通知",
        type="announcement",
        repeat_type=None,
        repeat_time=None,
        repeat_weekday=None,
        repeat_month_day=None,
        start_at=None,
        end_at=None,
        max_runs=None,
    )

    class FakeTask:
        @classmethod
        def filter(cls, **kwargs):
            return _AwaitableQuery([task])

    class FakeNotification:
        @classmethod
        async def create(cls, **kwargs):
            raise AssertionError("非目标用户不应创建通知")

    class FakeReceipt:
        @classmethod
        async def get_or_create(cls, **kwargs):
            raise AssertionError("非目标用户不应创建 receipt")

    monkeypatch.setattr(system_notification_service, "SystemNotificationTask", FakeTask)
    monkeypatch.setattr(system_notification_service, "SystemNotification", FakeNotification)
    monkeypatch.setattr(system_notification_service, "SystemNotificationReceipt", FakeReceipt)

    count = await system_notification_service.materialize_due_notifications_for_user(
        user_id=34,
        now=datetime(2026, 5, 17, 10, 0),
    )

    assert count == 0


@pytest.mark.asyncio
async def test_publish_due_task_accepts_timezone_aware_schedule_fields(monkeypatch: pytest.MonkeyPatch) -> None:
    saved = False
    published_schedules: list[datetime] = []

    async def fake_publish_task_once(task: object, *, scheduled_run_at: datetime | None = None) -> None:
        published_schedules.append(scheduled_run_at)

    class FakeTask(SimpleNamespace):
        async def save(self) -> None:
            nonlocal saved
            saved = True

    aware_zone = timezone(timedelta(hours=8))
    task = FakeTask(
        id=7,
        status="scheduled",
        send_mode="once",
        next_run_at=datetime(2026, 5, 17, 8, 0, tzinfo=aware_zone),
        publish_at=None,
        end_at=datetime(2026, 5, 18, 8, 0, tzinfo=aware_zone),
        max_runs=None,
        run_count=0,
        last_run_at=None,
    )

    monkeypatch.setattr(system_notification_service, "publish_task_once", fake_publish_task_once)

    await publish_due_task(task, now=datetime(2026, 5, 17, 8, 1))

    assert published_schedules == [datetime(2026, 5, 17, 8, 0)]
    assert task.last_run_at == datetime(2026, 5, 17, 8, 0)
    assert task.status == "completed"
    assert task.next_run_at is None
    assert saved is True
