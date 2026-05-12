from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest


class _Query:
    def __init__(self, *, first_value=None, values_value=None):
        self._first_value = first_value
        self._values_value = values_value or []

    async def first(self):
        return self._first_value

    async def values(self, *args):
        if args:
            return [{key: row[key] for key in args if key in row} for row in self._values_value]
        return self._values_value


class _FakeRedis:
    def __init__(self, *, set_result=True):
        self.set_result = set_result
        self.set_calls = []
        self.delete_calls = []

    async def set(self, *args, **kwargs):
        self.set_calls.append((args, kwargs))
        return self.set_result

    async def delete(self, key):
        self.delete_calls.append(key)
        return 1


@pytest.mark.asyncio
async def test_publish_balance_changed_pushes_low_balance_when_ongoing_call_needs_next_minute(monkeypatch):
    from app.services import balance_event_service as service

    user = SimpleNamespace(coins=Decimal("80"), diamonds=Decimal("3"))
    monkeypatch.setattr(service.AppUser, "filter", lambda **_: _Query(first_value=user))
    monkeypatch.setattr(
        service.CallRecord,
        "filter",
        lambda **_: _Query(values_value=[{"id": 7, "caller_id": 11, "callee_id": 22, "call_price": 100}]),
    )
    redis = _FakeRedis(set_result=True)
    monkeypatch.setattr(service, "get_redis", AsyncMock(return_value=redis))
    push_balance_update = AsyncMock()
    push_call_balance_low = AsyncMock()
    monkeypatch.setattr(service.ws_events, "push_balance_update", push_balance_update)
    monkeypatch.setattr(service.ws_events, "push_call_balance_low", push_call_balance_low)

    await service.publish_balance_changed(11, source="gift")

    push_balance_update.assert_awaited_once_with(user_id=11, coins=80.0, diamonds=3.0)
    push_call_balance_low.assert_awaited_once_with(
        caller_id=11,
        callee_id=22,
        payer_user_id=11,
        call_id=7,
        coins=80.0,
        required_coins=100,
        source="gift",
    )
    assert redis.set_calls == [
        (("call:7:balance_low:11", "1"), {"nx": True, "ex": 30}),
    ]


@pytest.mark.asyncio
async def test_publish_balance_changed_throttles_repeated_low_balance_push(monkeypatch):
    from app.services import balance_event_service as service

    user = SimpleNamespace(coins=Decimal("80"), diamonds=Decimal("3"))
    monkeypatch.setattr(service.AppUser, "filter", lambda **_: _Query(first_value=user))
    monkeypatch.setattr(
        service.CallRecord,
        "filter",
        lambda **_: _Query(values_value=[{"id": 7, "caller_id": 11, "callee_id": 22, "call_price": 100}]),
    )
    monkeypatch.setattr(service, "get_redis", AsyncMock(return_value=_FakeRedis(set_result=False)))
    monkeypatch.setattr(service.ws_events, "push_balance_update", AsyncMock())
    push_call_balance_low = AsyncMock()
    monkeypatch.setattr(service.ws_events, "push_call_balance_low", push_call_balance_low)

    await service.publish_balance_changed(11, source="call_heartbeat")

    push_call_balance_low.assert_not_awaited()


@pytest.mark.asyncio
async def test_publish_balance_changed_clears_low_balance_throttle_when_balance_recovers(monkeypatch):
    from app.services import balance_event_service as service

    user = SimpleNamespace(coins=Decimal("120"), diamonds=Decimal("3"))
    monkeypatch.setattr(service.AppUser, "filter", lambda **_: _Query(first_value=user))
    monkeypatch.setattr(
        service.CallRecord,
        "filter",
        lambda **_: _Query(values_value=[{"id": 7, "caller_id": 11, "callee_id": 22, "call_price": 100}]),
    )
    redis = _FakeRedis(set_result=True)
    monkeypatch.setattr(service, "get_redis", AsyncMock(return_value=redis))
    monkeypatch.setattr(service.ws_events, "push_balance_update", AsyncMock())
    push_call_balance_low = AsyncMock()
    monkeypatch.setattr(service.ws_events, "push_call_balance_low", push_call_balance_low)

    await service.publish_balance_changed(11, source="recharge")

    push_call_balance_low.assert_not_awaited()
    assert redis.delete_calls == ["call:7:balance_low:11"]


@pytest.mark.asyncio
async def test_push_call_balance_low_sends_warning_to_both_call_participants(monkeypatch):
    from app.websocket import events

    class _Manager:
        def __init__(self):
            self.pushes = []

        async def push_to_user(self, user_id, event, data, critical=False):
            self.pushes.append(
                {
                    "user_id": user_id,
                    "event": event,
                    "data": data,
                    "critical": critical,
                }
            )
            return True

    manager = _Manager()
    monkeypatch.setattr(events, "get_manager", lambda: manager)

    result = await events.push_call_balance_low(
        caller_id=11,
        callee_id=22,
        payer_user_id=11,
        call_id=7,
        coins=80.0,
        required_coins=100,
        source="gift",
    )

    assert result is True
    assert manager.pushes == [
        {
            "user_id": 11,
            "event": "call_balance_low",
            "data": {
                "call_id": 7,
                "payer_user_id": 11,
                "coins": 80.0,
                "required_coins": 100,
                "source": "gift",
            },
            "critical": False,
        },
        {
            "user_id": 22,
            "event": "call_balance_low",
            "data": {
                "call_id": 7,
                "payer_user_id": 11,
                "coins": 80.0,
                "required_coins": 100,
                "source": "gift",
            },
            "critical": False,
        },
    ]
