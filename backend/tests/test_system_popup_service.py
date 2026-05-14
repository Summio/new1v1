from datetime import datetime
from types import SimpleNamespace

import pytest

from app.services.system_popup_service import (
    PopupValidationError,
    ack_user_popup,
    build_popup_run_key,
    build_startup_popup_run_key,
    is_user_targeted_by_popup_task,
    normalize_user_ids,
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
    assert (
        build_startup_popup_run_key(task_id=8, user_id=34, launch_id="launch-1")
        == "popup_start:8:34:launch-1"
    )


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
