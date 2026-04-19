import unittest

from app.websocket.router import _HEARTBEAT_TIMEOUT, _PING_INTERVAL


class WebsocketHeartbeatPolicyTests(unittest.TestCase):
    def test_heartbeat_timeout_should_be_greater_than_ping_interval(self) -> None:
        self.assertGreater(
            _HEARTBEAT_TIMEOUT,
            _PING_INTERVAL,
            "服务端心跳超时必须大于客户端 ping 间隔，避免等值导致误判断线",
        )

