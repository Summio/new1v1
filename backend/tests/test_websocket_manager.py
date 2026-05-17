"""WebSocket Manager 集成测试。

测试 push_to_user -> redis.publish -> _send_ws 链路。

使用 mock Redis 验证：
- 在线用户推送成功
- 离线用户推送跳过
- 关键事件失败时记录 WARNING 日志
- PubSub 消息路由到正确的 worker
"""

from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest


@pytest.fixture(autouse=True)
def reset_pubsub_state():
    from app.websocket import manager as manager_module

    manager_module._pubsub_started = False
    manager_module._pubsub_task = None
    yield
    manager_module._pubsub_started = False
    manager_module._pubsub_task = None


class TestPushToUser:
    """测试 ConnectionManager.push_to_user 方法"""

    @pytest.fixture
    def manager(self):
        from app.websocket.manager import ConnectionManager

        return ConnectionManager()

    @pytest.mark.asyncio
    async def test_push_online_user_success(self, manager):
        """推送消息给在线用户时，应调用 redis.publish 并返回 True"""
        mock_redis = AsyncMock()
        mock_redis.sismember = AsyncMock(return_value=True)
        mock_redis.publish = AsyncMock(return_value=1)

        with patch("app.websocket.manager.get_redis", return_value=mock_redis):
            result = await manager.push_to_user(
                user_id=123,
                event="call_ended",
                data={"call_id": 1},
            )

        assert result is True
        mock_redis.sismember.assert_called_once()
        mock_redis.publish.assert_called_once()
        call_args = mock_redis.publish.call_args
        assert "ws:broadcast" in str(call_args)
        published_data = call_args[0][1]
        assert '"user_id":123' in published_data
        assert '"event":"call_ended"' in published_data

    @pytest.mark.asyncio
    async def test_push_offline_user_skipped(self, manager):
        """推送消息给离线用户时，应跳过 publish 并返回 False"""
        mock_redis = AsyncMock()
        mock_redis.sismember = AsyncMock(return_value=False)

        with patch("app.websocket.manager.get_redis", return_value=mock_redis):
            result = await manager.push_to_user(
                user_id=456,
                event="call_ended",
                data={"call_id": 2},
            )

        assert result is False
        mock_redis.sismember.assert_called_once()
        mock_redis.publish.assert_not_called()

    @pytest.mark.asyncio
    async def test_push_critical_event_failure_logs_warning(self, manager):
        """关键事件推送失败时，应记录 WARNING 日志"""
        mock_redis = AsyncMock()
        mock_redis.sismember = AsyncMock(return_value=True)
        mock_redis.publish = AsyncMock(side_effect=Exception("Redis unavailable"))

        with patch("app.websocket.manager.get_redis", return_value=mock_redis):
            with patch("app.websocket.manager.logger") as mock_logger:
                result = await manager.push_to_user(
                    user_id=789,
                    event="call_ended",
                    data={"call_id": 3},
                    critical=True,
                )

        assert result is False
        # 验证 WARNING 级别日志被调用
        assert mock_logger.warning.called
        warning_msg = str(mock_logger.warning.call_args)
        assert "critical" in warning_msg.lower() or "789" in warning_msg

    @pytest.mark.asyncio
    async def test_push_normal_event_failure_logs_warning(self, manager):
        """普通事件推送失败时，也应记录 WARNING 日志"""
        mock_redis = AsyncMock()
        mock_redis.sismember = AsyncMock(return_value=True)
        mock_redis.publish = AsyncMock(side_effect=Exception("Redis unavailable"))

        with patch("app.websocket.manager.get_redis", return_value=mock_redis):
            with patch("app.websocket.manager.logger") as mock_logger:
                result = await manager.push_to_user(
                    user_id=789,
                    event="gift_sent",
                    data={"gift_id": 1},
                )

        assert result is False
        assert mock_logger.warning.called


class TestPubsubLoopRouting:
    """测试 PubSub 消息路由：只有目标用户所在的 worker 才发送 WebSocket 帧"""

    @pytest.mark.asyncio
    async def test_message_routed_to_correct_worker(self):
        """同一消息广播到所有 worker，但只转发给目标用户"""
        from app.websocket.manager import ConnectionManager

        manager = ConnectionManager()

        # 模拟 WebSocket 连接：user 100 在本 worker，user 200 不在
        mock_ws_100 = AsyncMock()
        mock_ws_100.send_json = AsyncMock()

        async with manager._lock:
            manager._ws_conns[100] = mock_ws_100

        await manager._send_ws(100, {"type": "event", "event": "call_ended", "data": {}})

        mock_ws_100.send_json.assert_called_once_with({"type": "event", "event": "call_ended", "data": {}})

    @pytest.mark.asyncio
    async def test_message_ignored_when_user_not_connected(self):
        """目标用户不在本 worker 时，_send_ws 应返回 False"""
        from app.websocket.manager import ConnectionManager

        manager = ConnectionManager()

        # user 200 不在连接列表中
        result = await manager._send_ws(200, {"type": "event", "event": "call_ended", "data": {}})
        assert result is False

    @pytest.mark.asyncio
    async def test_stale_disconnect_should_not_remove_latest_connection(self):
        """同一用户新建连接后，旧连接断开不应影响当前活跃连接。"""
        from app.websocket.manager import ConnectionManager

        manager = ConnectionManager()
        mock_redis = AsyncMock()
        mock_redis.sadd = AsyncMock()
        mock_redis.setex = AsyncMock()
        mock_redis.set = AsyncMock()
        mock_redis.srem = AsyncMock()
        mock_redis.delete = AsyncMock()

        ws_old = AsyncMock()
        ws_old.send_json = AsyncMock()
        ws_old.close = AsyncMock()
        ws_new = AsyncMock()
        ws_new.send_json = AsyncMock()

        with patch("app.websocket.manager.get_redis", return_value=mock_redis):
            await manager.connect(100, ws_old)
            await manager.connect(100, ws_new)

            # 旧连接后到断开：不应移除 user=100 的当前连接（ws_new）
            await manager.disconnect(100, websocket=ws_old)
            sent = await manager._send_ws(100, {"type": "event", "event": "call_incoming", "data": {}})

        assert sent is True
        ws_new.send_json.assert_called_once_with({"type": "event", "event": "call_incoming", "data": {}})
        ws_old.send_json.assert_not_called()
        ws_old.close.assert_awaited_once_with(code=4000)

    @pytest.mark.asyncio
    async def test_cross_worker_stale_disconnect_should_not_mark_user_offline(self):
        """跨 worker 重连后，旧 worker 断开不应清掉新 worker 的在线标记。"""
        from app.websocket import manager as manager_module
        from app.websocket.manager import ConnectionManager

        class _FakeRedis:
            def __init__(self):
                self._sets: dict[str, set[int]] = {}
                self._strings: dict[str, str] = {}

            async def sadd(self, key: str, value: int):
                self._sets.setdefault(key, set()).add(int(value))
                return 1

            async def setex(self, key: str, _ttl: int, value: str):
                self._strings[key] = str(value)
                return True

            async def srem(self, key: str, value: int):
                self._sets.setdefault(key, set()).discard(int(value))
                return 1

            async def set(self, key: str, value):
                self._strings[key] = str(value)
                return True

            async def get(self, key: str):
                return self._strings.get(key)

            async def delete(self, key: str):
                self._strings.pop(key, None)
                return 1

        fake_redis = _FakeRedis()
        manager_a = ConnectionManager()
        manager_b = ConnectionManager()
        manager_a._pid = 101
        manager_b._pid = 202

        ws_a = AsyncMock()
        ws_a.send_json = AsyncMock()
        ws_b = AsyncMock()
        ws_b.send_json = AsyncMock()

        with patch("app.websocket.manager.get_redis", return_value=fake_redis):
            await manager_a.connect(100, ws_a)
            await manager_b.connect(100, ws_b)

            # 旧 worker 的连接晚到断开
            await manager_a.disconnect(100, websocket=ws_a)

            # 在线标记仍应保留给新 worker
            online_members = fake_redis._sets.get(manager_module._WS_ONLINE_KEY, set())
            self_pid_key = manager_module._user_pid_key(100)
            assert 100 in online_members
            assert fake_redis._strings.get(self_pid_key) == str(manager_b._pid)

    @pytest.mark.asyncio
    async def test_disconnect_awaits_offline_presence_broadcast(self):
        """当前 worker 清理全局在线状态时，应 await 下线广播。"""
        from app.websocket.manager import ConnectionManager

        class _FakeRedis:
            async def get(self, _key: str):
                return "101"

            async def srem(self, *_args):
                return 1

            async def delete(self, *_args):
                return 1

            async def zrem(self, *_args):
                return 1

        manager = ConnectionManager()
        manager._pid = 101
        ws = AsyncMock()
        async with manager._lock:
            manager._ws_conns[100] = ws

        with patch("app.websocket.manager.get_redis", return_value=_FakeRedis()):
            with patch("app.websocket.presence.get_redis", return_value=_FakeRedis()):
                with patch("app.websocket.presence.broadcast_presence", new_callable=AsyncMock) as mock_broadcast:
                    await manager.disconnect(100, websocket=ws)

        mock_broadcast.assert_awaited_once_with(manager=manager, user_id=100, online=False)


class TestOnlineLease:
    """测试在线租约，避免异常退出后 Redis 在线状态长期残留。"""

    @pytest.mark.asyncio
    async def test_connect_writes_online_lease_and_disconnect_deletes_it(self):
        from app.websocket import manager as manager_module
        from app.websocket.manager import ConnectionManager

        class _FakeRedis:
            def __init__(self):
                self.setex_calls: list[tuple[str, int, str]] = []
                self.deleted_keys: list[str] = []

            async def sadd(self, *_args):
                return 1

            async def setex(self, key: str, ttl: int, value: str):
                self.setex_calls.append((key, ttl, value))
                return True

            async def set(self, *_args):
                return True

            async def get(self, _key: str):
                return "101"

            async def srem(self, *_args):
                return 1

            async def delete(self, *keys):
                self.deleted_keys.extend(keys)
                return len(keys)

            async def zadd(self, *_args, **_kwargs):
                return 1

            async def zrem(self, *_args):
                return 1

        fake_redis = _FakeRedis()
        manager = ConnectionManager()
        manager._pid = 101
        ws = AsyncMock()

        with patch("app.websocket.manager.get_redis", return_value=fake_redis):
            with patch("app.websocket.presence.get_redis", return_value=fake_redis):
                await manager.connect(100, ws)
                await manager.disconnect(100, websocket=ws)

        lease_key = manager_module._online_lease_key(100)
        assert (lease_key, manager_module._ONLINE_LEASE_TTL_SECONDS, "1") in fake_redis.setex_calls
        assert lease_key in fake_redis.deleted_keys

    @pytest.mark.asyncio
    async def test_refresh_online_lease_only_refreshes_current_connection(self):
        from app.websocket import manager as manager_module
        from app.websocket.manager import ConnectionManager

        class _FakeRedis:
            def __init__(self):
                self.setex_calls: list[tuple[str, int, str]] = []

            async def setex(self, key: str, ttl: int, value: str):
                self.setex_calls.append((key, ttl, value))
                return True

        fake_redis = _FakeRedis()
        manager = ConnectionManager()
        ws_current = AsyncMock()
        ws_stale = AsyncMock()
        async with manager._lock:
            manager._ws_conns[100] = ws_current

        with patch("app.websocket.manager.get_redis", return_value=fake_redis):
            await manager.refresh_online_lease(100, websocket=ws_stale)
            await manager.refresh_online_lease(100, websocket=ws_current)

        assert fake_redis.setex_calls == [
            (
                manager_module._online_lease_key(100),
                manager_module._ONLINE_LEASE_TTL_SECONDS,
                "1",
            )
        ]

    @pytest.mark.asyncio
    async def test_presence_filters_stale_online_set_members_without_lease(self):
        from app.websocket import presence

        class _FakeRedis:
            def __init__(self):
                self.srem_calls: list[tuple] = []
                self.zrem_calls: list[tuple] = []

            async def smembers(self, _key: str):
                return {b"100", b"200"}

            async def mget(self, keys):
                if all(key.startswith("ws:online_lease:") for key in keys):
                    return ["1" if key.endswith(":100") else None for key in keys]
                if all(key.startswith("ws:manual_offline:") for key in keys):
                    return [None for _ in keys]
                return [None for _ in keys]

            async def srem(self, *args):
                self.srem_calls.append(args)
                return 1

            async def zrem(self, *args):
                self.zrem_calls.append(args)
                return 1

        fake_redis = _FakeRedis()
        with patch("app.websocket.presence.get_redis", return_value=fake_redis):
            online_ids = await presence.get_online_user_ids()

        assert online_ids == {100}
        assert ("ws:online", 200) in fake_redis.srem_calls

    @pytest.mark.asyncio
    async def test_presence_filter_degrades_to_offline_when_redis_times_out(self):
        from redis.exceptions import TimeoutError

        from app.websocket import presence

        class _FailingPipeline:
            def sismember(self, *_args):
                return self

            async def execute(self):
                raise TimeoutError("Timeout connecting to server")

        class _FailingRedis:
            def pipeline(self):
                return _FailingPipeline()

        with patch("app.websocket.presence.get_redis", return_value=_FailingRedis()):
            online_ids = await presence.filter_online_user_ids([100, 200])

        assert online_ids == set()


class TestCriticalEventMarkers:
    """测试关键事件集合标记"""

    def test_call_ended_is_critical(self):
        from app.websocket.manager import ConnectionManager

        manager = ConnectionManager()
        assert "call_ended" in manager._CRITICAL_EVENTS

    def test_call_timeout_is_critical(self):
        from app.websocket.manager import ConnectionManager

        manager = ConnectionManager()
        assert "call_timeout" in manager._CRITICAL_EVENTS

    def test_call_balance_empty_is_critical(self):
        from app.websocket.manager import ConnectionManager

        manager = ConnectionManager()
        assert "call_balance_empty" in manager._CRITICAL_EVENTS

    def test_balance_updated_is_critical(self):
        from app.websocket.manager import ConnectionManager

        manager = ConnectionManager()
        assert "balance_updated" in manager._CRITICAL_EVENTS


@pytest.mark.asyncio
async def test_pubsub_loop_closes_pubsub_before_retrying_after_listen_error():
    """Pub/Sub 监听异常后，重试前必须释放旧订阅连接。"""
    from redis.exceptions import TimeoutError

    from app.websocket.manager import ConnectionManager

    manager = ConnectionManager()
    manager._pubsub_running = True

    class FakePubSub:
        def __init__(self) -> None:
            self.unsubscribe = AsyncMock()
            self.close = AsyncMock()

        async def subscribe(self, _channel: str) -> None:
            return None

        async def listen(self):
            raise TimeoutError("Timeout reading from 127.0.0.1:6379")
            yield

    fake_pubsub = FakePubSub()
    fake_redis = MagicMock()
    fake_redis.pubsub.return_value = fake_pubsub

    async def fake_sleep(_delay: float) -> None:
        fake_pubsub.unsubscribe.assert_awaited_once()
        fake_pubsub.close.assert_awaited_once()
        raise asyncio.CancelledError

    with patch("app.websocket.manager._get_pubsub_redis", AsyncMock(return_value=fake_redis)):
        with patch("app.websocket.manager.asyncio.sleep", side_effect=fake_sleep):
            with pytest.raises(asyncio.CancelledError):
                await manager._pubsub_loop()


@pytest.mark.asyncio
async def test_pubsub_loop_uses_dedicated_redis_client():
    """Pub/Sub 监听不应复用普通业务 Redis client。"""
    from app.websocket.manager import ConnectionManager

    manager = ConnectionManager()
    manager._pubsub_running = True

    class FakePubSub:
        def __init__(self) -> None:
            self.unsubscribe = AsyncMock()
            self.close = AsyncMock()

        async def subscribe(self, _channel: str) -> None:
            return None

        async def listen(self):
            raise asyncio.CancelledError
            yield

    fake_redis = MagicMock()
    fake_redis.pubsub.return_value = FakePubSub()
    dedicated_getter = AsyncMock(return_value=fake_redis)

    async def fake_sleep(_delay: float) -> None:
        raise asyncio.CancelledError

    with patch("app.websocket.manager._get_pubsub_redis", dedicated_getter, create=True):
        with patch("app.websocket.manager.get_redis", side_effect=AssertionError("shared Redis client should not be used")):
            with patch("app.websocket.manager.asyncio.sleep", side_effect=fake_sleep):
                try:
                    await manager._pubsub_loop()
                except asyncio.CancelledError:
                    pass

    dedicated_getter.assert_awaited_once()


class TestPubsubLifecycle:
    """测试 PubSub 启停状态维护。"""

    @pytest.mark.asyncio
    async def test_start_pubsub_sets_running_true(self):
        from app.websocket.manager import ConnectionManager

        manager = ConnectionManager()
        fake_task = MagicMock()

        def _fake_create_task(coro):
            coro.close()
            return fake_task

        with patch("app.websocket.manager.asyncio.create_task", side_effect=_fake_create_task):
            await manager.start_pubsub()

        assert manager._pubsub_running is True
        assert manager._pubsub_task is fake_task

    @pytest.mark.asyncio
    async def test_stop_pubsub_resets_started_flag(self):
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
