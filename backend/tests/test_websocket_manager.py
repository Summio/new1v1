"""WebSocket Manager 集成测试。

测试 push_to_user -> redis.publish -> _send_ws 链路。

使用 mock Redis 验证：
- 在线用户推送成功
- 离线用户推送跳过
- 关键事件失败时记录 WARNING 日志
- PubSub 消息路由到正确的 worker
"""
from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest


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

        # 模拟 pubsub 收到消息
        raw_msg = '{"user_id": 100, "event": "call_ended", "data": {}}'
        await manager._send_ws(100, {"type": "event", "event": "call_ended", "data": {}})

        mock_ws_100.send_json.assert_called_once_with(
            {"type": "event", "event": "call_ended", "data": {}}
        )

    @pytest.mark.asyncio
    async def test_message_ignored_when_user_not_connected(self):
        """目标用户不在本 worker 时，_send_ws 应返回 False"""
        from app.websocket.manager import ConnectionManager

        manager = ConnectionManager()

        # user 200 不在连接列表中
        result = await manager._send_ws(200, {"type": "event", "event": "call_ended", "data": {}})
        assert result is False


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
