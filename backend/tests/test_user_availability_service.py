from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest


class _ValuesQuery:
    def __init__(self, rows):
        self.rows = rows
        self.filters = []

    def filter(self, *args, **kwargs):
        self.filters.append((args, kwargs))
        return self

    async def values(self, *fields):
        return self.rows


def _user(user_id: int, *, video_dnd_enabled: bool = False):
    return SimpleNamespace(id=user_id, video_dnd_enabled=video_dnd_enabled)


def test_resolve_availability_payload_respects_priority() -> None:
    from app.services.user_availability_service import resolve_availability_payload

    assert resolve_availability_payload(_user(1), is_online=False, is_busy=False) == {
        "is_online": False,
        "is_busy": False,
        "video_dnd_enabled": False,
        "availability_status": "offline",
        "availability_label": "离线",
    }
    assert resolve_availability_payload(_user(2, video_dnd_enabled=True), is_online=True, is_busy=True) == {
        "is_online": True,
        "is_busy": True,
        "video_dnd_enabled": True,
        "availability_status": "dnd",
        "availability_label": "勿扰",
    }
    assert resolve_availability_payload(_user(3), is_online=True, is_busy=True)["availability_status"] == "busy"
    assert resolve_availability_payload(_user(4), is_online=True, is_busy=False)["availability_status"] == "online"


@pytest.mark.asyncio
async def test_get_busy_user_ids_collects_call_participants(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import user_availability_service as service

    query = _ValuesQuery(
        [
            {"caller_id": 1, "callee_id": 2},
            {"caller_id": 3, "callee_id": 4},
            {"caller_id": 9, "callee_id": 2},
        ]
    )
    monkeypatch.setattr(service.CallRecord, "filter", lambda **kwargs: query)

    assert await service.get_busy_user_ids([2, 3, 5]) == {2, 3}


@pytest.mark.asyncio
async def test_build_availability_payload_map_uses_shared_resolver(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import user_availability_service as service

    monkeypatch.setattr(service, "get_busy_user_ids", AsyncMock(return_value={2, 3}))

    payloads = await service.build_availability_payload_map(
        [_user(1), _user(2), _user(3, video_dnd_enabled=True), _user(4)],
        online_ids={1, 2, 3},
    )

    assert payloads[1]["availability_status"] == "online"
    assert payloads[2]["availability_status"] == "busy"
    assert payloads[3]["availability_status"] == "dnd"
    assert payloads[4]["availability_status"] == "offline"


@pytest.mark.asyncio
async def test_push_presence_broadcasts_full_payload_to_online_users(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.websocket import events

    payload = {
        "user_id": 9,
        "online": True,
        "is_online": True,
        "is_busy": True,
        "video_dnd_enabled": False,
        "availability_status": "busy",
        "availability_label": "忙碌",
    }
    monkeypatch.setattr(
        events,
        "build_user_availability_event_payload",
        AsyncMock(return_value=payload),
        raising=False,
    )
    monkeypatch.setattr(events, "get_online_user_ids", AsyncMock(return_value={1, 2, 3}), raising=False)

    push_calls = []

    class _Manager:
        async def push_to_user(self, user_id, event, data, critical=False):
            push_calls.append((user_id, event, data, critical))
            return True

    monkeypatch.setattr(events, "get_manager", lambda: _Manager())

    assert await events.push_presence(user_id=9, online=True) is True
    assert push_calls == [
        (1, "presence", payload, True),
        (2, "presence", payload, True),
        (3, "presence", payload, True),
    ]
