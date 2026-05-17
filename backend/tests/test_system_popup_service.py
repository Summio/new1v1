from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

from app.services import system_popup_service
from app.services.system_popup_service import (
    PopupValidationError,
    ack_user_popup,
    build_popup_run_key,
    build_startup_popup_run_key,
    fetch_startup_popups_for_user,
    is_user_targeted_by_popup_task,
    normalize_user_ids,
    publish_due_popup_task,
    publish_popup_task_once,
    validate_popup_task_payload,
)


def test_validate_popup_payload_requires_title_and_content() -> None:
    base = {
        "title": "Notice",
        "content": "Hello",
        "type": "announcement",
        "send_mode": "immediate",
        "status": "scheduled",
        "target_mode": "all",
    }

    with pytest.raises(PopupValidationError, match="标题不能为空"):
        validate_popup_task_payload({**base, "title": " "})

    with pytest.raises(PopupValidationError, match="正文不能为空"):
        validate_popup_task_payload({**base, "content": " "})


def test_validate_popup_payload_rejects_online_filter_and_requires_repeat_end() -> None:
    base = {
        "title": "Notice",
        "content": "Hello",
        "type": "announcement",
        "send_mode": "immediate",
        "status": "scheduled",
        "target_mode": "filter",
    }

    with pytest.raises(PopupValidationError, match="不支持的筛选条件"):
        validate_popup_task_payload({**base, "target_filters": {"is_online": True}})

    with pytest.raises(PopupValidationError, match="周期重复必须填写结束时间或最大发送次数"):
        validate_popup_task_payload(
            {
                **base,
                "target_mode": "all",
                "send_mode": "repeat",
                "repeat_type": "daily",
                "repeat_time": "10:00",
            }
        )


def test_normalize_user_ids_and_run_key_are_stable() -> None:
    assert normalize_user_ids("3, 1, 3,2") == [1, 2, 3]
    assert normalize_user_ids([2, "1", "2"]) == [1, 2]
    assert (
        build_popup_run_key(task_id=8, scheduled_run_at=datetime(2026, 5, 14, 10, 0))
        == "popup_task:8:2026-05-14T10:00:00"
    )
    assert build_startup_popup_run_key(task_id=8, user_id=34, launch_id="launch-1") == "popup_start:8:34:launch-1"


def test_validate_popup_payload_accepts_app_start_without_schedule() -> None:
    payload = validate_popup_task_payload(
        {
            "title": "Notice",
            "content": "Hello",
            "type": "announcement",
            "send_mode": "app_start",
            "status": "scheduled",
            "target_mode": "all",
        }
    )

    assert payload["send_mode"] == "app_start"
    assert payload["publish_at"] is None
    assert payload["repeat_type"] is None


@pytest.mark.asyncio
async def test_is_user_targeted_by_popup_task_supports_all_user_ids_and_filters(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    assert await is_user_targeted_by_popup_task(
        user_id=12,
        target_mode="all",
        target_user_ids=[],
        target_filters=None,
    )
    assert await is_user_targeted_by_popup_task(
        user_id=12,
        target_mode="user_ids",
        target_user_ids=[3, 12],
        target_filters=None,
    )
    assert not await is_user_targeted_by_popup_task(
        user_id=12,
        target_mode="user_ids",
        target_user_ids=[3, 4],
        target_filters=None,
    )

    class FakeQuery:
        async def exists(self):
            return True

    class FakeAppUser:
        @classmethod
        def filter(cls, *args, **kwargs):
            assert kwargs == {"id": 12}
            return FakeQuery()

    monkeypatch.setattr("app.services.system_popup_service.AppUser", FakeAppUser)

    assert await is_user_targeted_by_popup_task(
        user_id=12,
        target_mode="filter",
        target_user_ids=[],
        target_filters={"gender": "female"},
    )


@pytest.mark.asyncio
async def test_ack_user_popup_is_idempotent(monkeypatch: pytest.MonkeyPatch) -> None:
    saved = {"count": 0}
    receipt = SimpleNamespace(ack_at=None)

    async def fake_save() -> None:
        saved["count"] += 1

    receipt.save = fake_save

    class FakeQuery:
        async def first(self):
            return receipt

    class FakeReceipt:
        @classmethod
        def filter(cls, **kwargs):
            assert kwargs == {"popup_id": 12, "user_id": 34}
            return FakeQuery()

    monkeypatch.setattr("app.services.system_popup_service.SystemPopupReceipt", FakeReceipt)
    monkeypatch.setattr(
        "app.services.system_popup_service.now_local_naive",
        lambda: datetime(2026, 5, 14, 10, 30),
    )

    assert await ack_user_popup(user_id=34, popup_id=12) is True
    assert receipt.ack_at == datetime(2026, 5, 14, 10, 30)
    assert saved["count"] == 1

    assert await ack_user_popup(user_id=34, popup_id=12) is True
    assert saved["count"] == 1


@pytest.mark.asyncio
async def test_publish_popup_task_once_creates_popup_without_online_filter_receipts_or_push(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    task = SimpleNamespace(
        id=8,
        next_run_at=datetime(2026, 5, 14, 10, 0),
        publish_at=None,
        target_mode="all",
        target_user_ids=[],
        target_filters=None,
        title="Notice",
        content="Hello",
        type="announcement",
    )

    class FakeTransaction:
        async def __aenter__(self) -> None:
            return None

        async def __aexit__(self, *_: object) -> None:
            return None

    class FakePopupQuery:
        async def first(self):
            return None

    class FakePopup:
        id = 88

        @classmethod
        def filter(cls, **kwargs):
            return FakePopupQuery()

        @classmethod
        async def create(cls, **kwargs):
            assert kwargs["task_id"] == 8
            assert kwargs["title"] == "Notice"
            assert kwargs["content"] == "Hello"
            return cls()

    async def fail_resolve_online_target_user_ids(**kwargs):
        raise AssertionError("发布弹窗不应再筛选在线用户")

    class FakeReceipt:
        @classmethod
        async def bulk_create(cls, *args, **kwargs):
            raise AssertionError("发布弹窗不应再批量创建在线用户 receipt")

    monkeypatch.setattr("app.services.system_popup_service.SystemPopup", FakePopup)
    monkeypatch.setattr("app.services.system_popup_service.SystemPopupReceipt", FakeReceipt)
    monkeypatch.setattr(
        "app.services.system_popup_service.resolve_online_target_user_ids",
        fail_resolve_online_target_user_ids,
        raising=False,
    )
    monkeypatch.setattr("app.services.system_popup_service.in_transaction", lambda: FakeTransaction())

    popup = await publish_popup_task_once(task)

    assert isinstance(popup, FakePopup)


@pytest.mark.asyncio
async def test_fetch_pending_popups_returns_targeted_unacked_items_and_creates_receipts(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    task_targeted = SimpleNamespace(id=8, target_mode="all", target_user_ids=[], target_filters=None)
    task_not_targeted = SimpleNamespace(id=9, target_mode="user_ids", target_user_ids=[99], target_filters=None)
    popups = [
        SimpleNamespace(
            id=1,
            title="Notice 1",
            content="Hello 1",
            type="announcement",
            publish_at=None,
            published_at=datetime(2026, 5, 14, 10, 1),
            task=task_targeted,
        ),
        SimpleNamespace(
            id=2,
            title="Notice 2",
            content="Hello 2",
            type="announcement",
            publish_at=None,
            published_at=datetime(2026, 5, 14, 10, 2),
            task=task_targeted,
        ),
        SimpleNamespace(
            id=3,
            title="Notice 3",
            content="Hello 3",
            type="announcement",
            publish_at=None,
            published_at=datetime(2026, 5, 14, 10, 3),
            task=task_not_targeted,
        ),
    ]
    created_receipts: list[tuple[int, int]] = []

    class FakePopupQuery:
        def order_by(self, *args):
            return self

        def limit(self, value):
            return self

        def __await__(self):
            async def _result():
                return popups

            return _result().__await__()

    class FakePopup:
        @classmethod
        def filter(cls, **kwargs):
            assert kwargs == {"published_at__not_isnull": True}
            return FakePopupQuery()

    class FakeReceiptQuery:
        def __init__(self, popup_id: int):
            self.popup_id = popup_id

        async def first(self):
            if self.popup_id == 2:
                return SimpleNamespace(ack_at=datetime(2026, 5, 14, 10, 5))
            return None

    class FakeReceipt:
        @classmethod
        def filter(cls, **kwargs):
            assert kwargs["user_id"] == 34
            return FakeReceiptQuery(kwargs["popup_id"])

        @classmethod
        async def get_or_create(cls, **kwargs):
            created_receipts.append((kwargs["popup_id"], kwargs["user_id"]))
            return SimpleNamespace(ack_at=None), True

    monkeypatch.setattr("app.services.system_popup_service.SystemPopup", FakePopup)
    monkeypatch.setattr("app.services.system_popup_service.SystemPopupReceipt", FakeReceipt)

    items = await system_popup_service.fetch_pending_popups_for_user(user_id=34)

    assert [item["id"] for item in items] == [1]
    assert created_receipts == [(1, 34)]


@pytest.mark.asyncio
async def test_publish_due_popup_task_accepts_timezone_aware_schedule_fields(monkeypatch: pytest.MonkeyPatch) -> None:
    saved = False
    published_schedules: list[datetime] = []

    async def fake_publish_popup_task_once(task: object, *, scheduled_run_at: datetime | None = None) -> None:
        published_schedules.append(scheduled_run_at)

    class FakeTask(SimpleNamespace):
        async def save(self) -> None:
            nonlocal saved
            saved = True

    aware_zone = timezone(timedelta(hours=8))
    task = FakeTask(
        id=8,
        status="scheduled",
        send_mode="once",
        next_run_at=datetime(2026, 5, 14, 10, 0, tzinfo=aware_zone),
        publish_at=None,
        end_at=datetime(2026, 5, 15, 10, 0, tzinfo=aware_zone),
        max_runs=None,
        run_count=0,
        last_run_at=None,
    )

    monkeypatch.setattr("app.services.system_popup_service.publish_popup_task_once", fake_publish_popup_task_once)

    await publish_due_popup_task(task, now=datetime(2026, 5, 14, 10, 1))

    assert published_schedules == [datetime(2026, 5, 14, 10, 0)]
    assert task.last_run_at == datetime(2026, 5, 14, 10, 0)
    assert task.status == "completed"
    assert task.next_run_at is None
    assert saved is True


@pytest.mark.asyncio
async def test_fetch_startup_popups_limits_running_tasks_and_returned_items(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    queried = {"limit": None}
    tasks = [
        SimpleNamespace(
            id=index,
            title=f"Notice {index}",
            content="Hello",
            type="announcement",
            target_mode="all",
            target_user_ids=[],
            target_filters=None,
        )
        for index in range(1, 8)
    ]

    class FakeTaskQuery:
        def __init__(self):
            self.items = tasks

        def order_by(self, *args):
            return self

        def limit(self, value):
            queried["limit"] = value
            self.items = tasks[:value]
            return self

        def __await__(self):
            async def _result():
                return self.items

            return _result().__await__()

    class FakeTask:
        @classmethod
        def filter(cls, **kwargs):
            assert kwargs == {"send_mode": "app_start", "status": "running"}
            return FakeTaskQuery()

    class FakePopupQuery:
        def __init__(self, run_key):
            self.run_key = run_key

        async def first(self):
            task_id = int(self.run_key.split(":")[1])
            return SimpleNamespace(
                id=task_id,
                title=f"Notice {task_id}",
                content="Hello",
                type="announcement",
                published_at=datetime(2026, 5, 14, 10, task_id),
                publish_at=None,
            )

    class FakePopup:
        @classmethod
        def filter(cls, **kwargs):
            return FakePopupQuery(kwargs["run_key"])

    class FakeReceipt:
        @classmethod
        async def get_or_create(cls, **kwargs):
            return SimpleNamespace(), False

    monkeypatch.setattr("app.services.system_popup_service.SystemPopupTask", FakeTask)
    monkeypatch.setattr("app.services.system_popup_service.SystemPopup", FakePopup)
    monkeypatch.setattr("app.services.system_popup_service.SystemPopupReceipt", FakeReceipt)

    items = await fetch_startup_popups_for_user(user_id=34, launch_id="launch-1")

    assert queried["limit"] == 5
    assert len(items) == 3
    assert [item["title"] for item in items] == ["Notice 1", "Notice 2", "Notice 3"]
