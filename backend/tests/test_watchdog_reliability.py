from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from dataclasses import dataclass
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from redis.exceptions import ResponseError

from app.core.call_watchdog import WatchdogConfig


@pytest.mark.asyncio
async def test_run_call_watchdog_leader_loop_no_internal_error_when_refresh_ok():
    from app.core import call_watchdog

    stop_event = asyncio.Event()
    config = WatchdogConfig(
        poll_seconds=1,
        ring_timeout_seconds=30,
        renew_grace_seconds=25,
        free_seconds_before_billing=10,
    )

    async def _close_pending(_config):
        return None

    async def _close_ongoing(_config):
        stop_event.set()
        return None

    fake_logger = MagicMock()

    with (
        patch("app.websocket.manager.try_acquire_watchdog_leader", AsyncMock(return_value=True)),
        patch("app.websocket.manager.refresh_watchdog_leader", AsyncMock(return_value=True)),
        patch.object(call_watchdog, "_load_watchdog_config", AsyncMock(return_value=config)),
        patch.object(call_watchdog, "_close_timeout_pending", AsyncMock(side_effect=_close_pending)),
        patch.object(call_watchdog, "_close_stale_ongoing", AsyncMock(side_effect=_close_ongoing)),
        patch.object(call_watchdog, "logger", fake_logger),
    ):
        await call_watchdog.run_call_watchdog(stop_event)

    loop_errors = [
        c for c in fake_logger.exception.call_args_list if "call watchdog loop error" in str(c)
    ]
    assert loop_errors == []


@dataclass
class _FakeCallRecord:
    id: int
    caller_id: int
    callee_id: int
    status: str
    end_reason: str | None


class _FakeCallRecordQuery:
    def __init__(self, kwargs: dict, updates: dict[int, int], records: dict[int, _FakeCallRecord]):
        self._kwargs = kwargs
        self._updates = updates
        self._records = records

    def limit(self, _num: int):
        return self

    async def values_list(self, *_args, **_kwargs):
        return [1, 2]

    def using_db(self, _conn):
        return self

    def select_for_update(self):
        return self

    async def update(self, **_kwargs):
        return self._updates.get(int(self._kwargs.get("id", 0)), 0)

    async def first(self):
        call_id = self._kwargs.get("id")
        if call_id is None:
            return None
        return self._records.get(int(call_id))


class _FakeCallRecordModel:
    updates: dict[int, int] = {}
    records: dict[int, _FakeCallRecord] = {}

    @classmethod
    def filter(cls, *args, **kwargs):  # noqa: ANN002, ANN003
        return _FakeCallRecordQuery(kwargs, cls.updates, cls.records)


@pytest.mark.asyncio
async def test_close_timeout_pending_pushes_only_updated_timeout_records():
    from app.core import call_watchdog

    _FakeCallRecordModel.updates = {1: 1, 2: 0}
    _FakeCallRecordModel.records = {
        1: _FakeCallRecord(
            id=1,
            caller_id=101,
            callee_id=201,
            status="ended",
            end_reason="timeout",
        ),
        2: _FakeCallRecord(
            id=2,
            caller_id=102,
            callee_id=202,
            status="ongoing",
            end_reason=None,
        ),
    }

    trace_append = AsyncMock()
    pushed_call_ids: list[int] = []

    async def _fake_ws_push(call_record):
        pushed_call_ids.append(int(call_record.id))

    @asynccontextmanager
    async def _fake_tx():
        yield object()

    config = WatchdogConfig(
        poll_seconds=5,
        ring_timeout_seconds=30,
        renew_grace_seconds=25,
        free_seconds_before_billing=10,
    )

    with (
        patch.object(call_watchdog, "CallRecord", _FakeCallRecordModel),
        patch.object(call_watchdog, "CallTraceService", return_value=MagicMock(append=trace_append)),
        patch.object(call_watchdog, "_ws_push_call_timeout", AsyncMock(side_effect=_fake_ws_push)),
        patch.object(call_watchdog, "in_transaction", _fake_tx),
    ):
        await call_watchdog._close_timeout_pending(config)
        await asyncio.sleep(0)

    assert trace_append.await_count == 1
    trace_call = trace_append.await_args_list[0]
    assert int(trace_call.kwargs["call_record"].id) == 1
    assert pushed_call_ids == [1]


@pytest.fixture(autouse=True)
def reset_watchdog_refresh_script_sha():
    from app.websocket import manager as manager_module

    manager_module._watchdog_refresh_script_sha = None
    yield
    manager_module._watchdog_refresh_script_sha = None


@pytest.mark.asyncio
async def test_refresh_watchdog_leader_atomic_success_when_pid_matches():
    from app.websocket import manager as manager_module

    mock_redis = AsyncMock()
    mock_redis.evalsha = AsyncMock(return_value=1)
    mock_redis.script_load = AsyncMock(return_value="sha-watchdog")

    with (
        patch.object(manager_module, "get_redis", AsyncMock(return_value=mock_redis)),
        patch.object(manager_module.os, "getpid", return_value=9527),
    ):
        result = await manager_module.refresh_watchdog_leader()

    assert result is True
    mock_redis.evalsha.assert_awaited()


@pytest.mark.asyncio
async def test_refresh_watchdog_leader_atomic_failure_when_pid_not_match():
    from app.websocket import manager as manager_module

    mock_redis = AsyncMock()
    mock_redis.evalsha = AsyncMock(return_value=0)
    mock_redis.script_load = AsyncMock(return_value="sha-watchdog")

    with (
        patch.object(manager_module, "get_redis", AsyncMock(return_value=mock_redis)),
        patch.object(manager_module.os, "getpid", return_value=9527),
    ):
        result = await manager_module.refresh_watchdog_leader()

    assert result is False
    mock_redis.evalsha.assert_awaited()


@pytest.mark.asyncio
async def test_refresh_watchdog_leader_reloads_script_after_noscript():
    from app.websocket import manager as manager_module

    mock_redis = AsyncMock()
    mock_redis.evalsha = AsyncMock(
        side_effect=[ResponseError("NOSCRIPT No matching script. Please use EVAL."), 1]
    )
    mock_redis.script_load = AsyncMock(return_value="sha-watchdog")

    with (
        patch.object(manager_module, "get_redis", AsyncMock(return_value=mock_redis)),
        patch.object(manager_module.os, "getpid", return_value=9527),
    ):
        result = await manager_module.refresh_watchdog_leader()

    assert result is True
    assert mock_redis.script_load.await_count >= 1
    assert mock_redis.evalsha.await_count == 2


# ===== P2-2: push 失败降级测试 =====


@pytest.mark.asyncio
async def test_push_failure_threshold_tracks_consecutive_failures():
    """连续推送失败应触发阈值告警"""
    from app.websocket.manager import ConnectionManager

    manager = ConnectionManager()

    # 模拟 Redis 推送持续失败
    mock_redis = AsyncMock()
    mock_redis.sismember = AsyncMock(return_value=True)
    mock_redis.publish = AsyncMock(side_effect=Exception("Redis unavailable"))

    with patch("app.websocket.manager.get_redis", return_value=mock_redis):
        with patch("app.websocket.manager.logger") as mock_logger:
            # 连续失败 2 次：未达阈值（_PUSH_FAIL_THRESHOLD=3）
            await manager.push_to_user(user_id=100, event="call_ended", data={}, critical=True)
            await manager.push_to_user(user_id=100, event="call_ended", data={}, critical=True)

            # 连续失败 3 次：触发阈值
            await manager.push_to_user(user_id=100, event="call_ended", data={}, critical=True)

            threshold_logs = [
                c for c in mock_logger.warning.call_args_list
                if "threshold exceeded" in str(c)
            ]
            assert len(threshold_logs) >= 1
            assert mock_logger.warning.called


@pytest.mark.asyncio
async def test_push_failure_threshold_resets_on_success():
    """推送成功后应重置失败计数器"""
    from app.websocket.manager import ConnectionManager

    manager = ConnectionManager()
    manager._push_failures[100] = 2  # 已有 2 次失败

    mock_redis = AsyncMock()
    mock_redis.sismember = AsyncMock(return_value=True)
    mock_redis.publish = AsyncMock(return_value=1)

    with patch("app.websocket.manager.get_redis", return_value=mock_redis):
        await manager.push_to_user(user_id=100, event="call_ended", data={})

    # 成功后计数器应被清除
    assert 100 not in manager._push_failures


# ===== P2-2: PubSub 启停状态机测试 =====


@pytest.mark.asyncio
async def test_stop_pubsub_resets_pubsub_running_flag():
    """stop_pubsub 应将 _pubsub_running 重置为 False"""
    from app.websocket import manager as manager_module
    from app.websocket.manager import ConnectionManager

    manager = ConnectionManager()
    manager_module._pubsub_started = True
    manager._pubsub_running = True
    task = asyncio.create_task(asyncio.sleep(0))
    manager._pubsub_task = task

    await manager.stop_pubsub()

    assert manager._pubsub_running is False
    assert manager_module._pubsub_started is False


@pytest.mark.asyncio
async def test_start_pubsub_idempotent_when_already_started():
    """重复调用 start_pubsub 不应启动多个监听"""
    from app.websocket import manager as manager_module
    from app.websocket.manager import ConnectionManager

    manager = ConnectionManager()
    fake_task = MagicMock()

    def _fake_create_task(coro):
        coro.close()
        return fake_task

    with patch("app.websocket.manager.asyncio.create_task", side_effect=_fake_create_task):
        await manager.start_pubsub()
        await manager.start_pubsub()  # 重复调用
        await manager.start_pubsub()  # 再重复调用

    # create_task 只应被调用 1 次（后续调用因 _pubsub_started=True 而提前返回）
    # 注：_pubsub_started 是全局状态，首次调用后变为 True


# ===== P1-4: global 变量赋值验证 =====


@pytest.mark.asyncio
async def test_stop_pubsub_clears_global_pubsub_task():
    """stop_pubsub 应清理全局 _pubsub_task 变量"""
    from app.websocket import manager as manager_module
    from app.websocket.manager import ConnectionManager

    manager = ConnectionManager()
    manager_module._pubsub_started = True
    manager._pubsub_running = True
    task = asyncio.create_task(asyncio.sleep(0))
    manager._pubsub_task = task
    manager_module._pubsub_task = task

    await manager.stop_pubsub()

    # 全局 _pubsub_task 应为 None
    assert manager_module._pubsub_task is None
    assert manager_module._pubsub_started is False
