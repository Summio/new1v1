"""WebSocket 连接管理器。

Redis Pub/Sub 版：支持多 worker 部署，每个 worker 维护自己的连接，
通过 Redis Pub/Sub 广播消息，目标 worker 收到后转发到本地 WebSocket。

Redis Key 设计：
  ws:online              - SET，所有在线用户 ID
  ws:user:{user_id}:pid  - STRING，用户所在进程 PID（连接时设，断开时删）
  ws:pid:{pid}:users    - SET，该进程所有连接用户（连接时增，断开时删）
  ws:broadcast           - Pub/Sub 频道，跨实例消息广播

Watchdog Leader Election：
  watchdog:leader        - STRING，当前 leader 的 PID（SET NX EX 60s）
"""

from __future__ import annotations

import asyncio
import json
import os
from typing import Any

from loguru import logger

from app.core.redis import get_redis

# ===== Redis Key Builders =====

_WS_ONLINE_KEY = "ws:online"
_WS_BROADCAST_CHANNEL = "ws:broadcast"
_WATCHDOG_LEADER_KEY = "watchdog:leader"
_WATCHDOG_LEADER_TTL = 60  # 秒，leader 续期间隔


def _user_pid_key(user_id: int) -> str:
    return f"ws:user:{user_id}:pid"


def _pid_users_key(pid: int) -> str:
    return f"ws:pid:{pid}:users"


# ===== Connection Manager =====

_connected: dict[int, Any] = {}  # user_id -> WebSocket（模块级，本 worker 内存）
_connected_lock = asyncio.Lock()
_pubsub_started = False
_pubsub_started_lock = asyncio.Lock()
_pubsub_task: asyncio.Task | None = None
_redis_client_for_pubsub: Any = None  # 独立 Redis 连接用于 pub/sub


class ConnectionManager:
    """本 worker 的 WebSocket 连接管理器 + Redis Pub/Sub 广播。"""

    def __init__(self) -> None:
        self._pid = os.getpid()
        self._ws_conns: dict[int, Any] = {}
        self._lock = asyncio.Lock()
        self._pubsub: Any = None
        self._pubsub_task: asyncio.Task | None = None
        self._pubsub_running = False

    # ===== 本实例连接管理 =====

    async def connect(self, user_id: int, websocket: Any) -> None:
        """将用户 WebSocket 连接注册到本实例。"""
        async with self._lock:
            self._ws_conns[user_id] = websocket

        # 更新 Redis 在线状态
        try:
            redis = await get_redis()
            await redis.sadd(_WS_ONLINE_KEY, user_id)
            await redis.set(_user_pid_key(user_id), self._pid)
            await redis.sadd(_pid_users_key(self._pid), user_id)
            logger.info(f"[WS] user {user_id} connected on pid {self._pid}, total={len(self._ws_conns)}")
        except Exception as e:
            logger.warning(f"[WS] Redis update failed on connect: {e}")

    async def disconnect(self, user_id: int) -> None:
        """将用户 WebSocket 连接从本实例移除。"""
        removed = False
        async with self._lock:
            if user_id in self._ws_conns:
                del self._ws_conns[user_id]
                removed = True
                logger.info(f"[WS] user {user_id} disconnected from pid {self._pid}, remaining={len(self._ws_conns)}")

        if not removed:
            return

        # 更新 Redis 在线状态
        try:
            redis = await get_redis()
            await redis.srem(_WS_ONLINE_KEY, user_id)
            await redis.delete(_user_pid_key(user_id))
            await redis.srem(_pid_users_key(self._pid), user_id)
        except Exception as e:
            logger.warning(f"[WS] Redis update failed on disconnect: {e}")

    async def _send_ws(self, user_id: int, payload: dict) -> bool:
        """向本实例的 WebSocket 发送消息，不存在则静默忽略。"""
        async with self._lock:
            ws = self._ws_conns.get(user_id)

        if ws is None:
            return False

        try:
            await ws.send_json(payload)
            return True
        except Exception as e:
            logger.warning(f"[WS] send to user {user_id} failed, disconnecting: {e}")
            await self.disconnect(user_id)
            return False

    # ===== 跨实例推送 =====

    # ===== 关键事件标记 =====
    _CRITICAL_EVENTS = frozenset({
        "call_ended",
        "call_timeout",
        "call_balance_empty",
        "balance_updated",
    })

    async def push_to_user(
        self, user_id: int, event: str, data: dict, critical: bool = False,
    ) -> bool:
        """通过 Redis Pub/Sub 推送事件给目标用户。

        发布到 ws:broadcast 频道，消息格式：
          {"user_id": int, "event": str, "data": dict}

        所有 worker 都会收到消息，只有目标用户所在的 worker 会实际发送 WebSocket 帧。

        Args:
            user_id: 目标用户 ID
            event: 事件名称
            data: 事件数据
            critical: 是否为关键事件，关键事件失败时记录 WARNING 日志
        """
        try:
            redis = await get_redis()
            # 检查用户是否在线
            online = await redis.sismember(_WS_ONLINE_KEY, user_id)
            if not online:
                logger.debug(f"[WS] push skipped: user {user_id} not online")
                return False

            msg = json.dumps(
                {"user_id": user_id, "event": event, "data": data},
                ensure_ascii=False,
                separators=(",", ":"),
            )
            await redis.publish(_WS_BROADCAST_CHANNEL, msg)
            return True
        except Exception as e:
            # W-4 修复：关键事件失败时记录 WARNING 日志用于监控
            if critical or event in self._CRITICAL_EVENTS:
                logger.warning(f"[WS] critical push_to_user({user_id}, {event}) failed: {e}")
            else:
                logger.warning(f"[WS] push_to_user({user_id}, {event}) failed: {e}")
            return False

    # ===== Pub/Sub 监听循环 =====

    async def start_pubsub(self) -> None:
        """启动 Redis Pub/Sub 监听（在每个 worker 进程启动时调用一次）。"""
        global _pubsub_started, _pubsub_task

        async with _pubsub_started_lock:
            if _pubsub_started:
                return
            _pubsub_started = True

        logger.info(f"[WS] starting pubsub listener on pid {self._pid}")
        _pubsub_task = asyncio.create_task(self._pubsub_loop())
        self._pubsub_task = _pubsub_task

    async def _pubsub_loop(self) -> None:
        """Pub/Sub 监听循环，支持断线重连。"""
        delay = 1.0
        while True:
            try:
                # 使用独立 Redis 连接订阅（不影响主 Redis 连接池）
                redis = await get_redis()
                self._pubsub = redis.pubsub()
                await self._pubsub.subscribe(_WS_BROADCAST_CHANNEL)
                delay = 1.0  # 重连成功后重置延迟
                logger.info(f"[WS] pubsub subscribed to {_WS_BROADCAST_CHANNEL}")

                async for raw in self._pubsub.listen():
                    if not self._pubsub_running:
                        break
                    if raw.get("type") != "message":
                        continue

                    try:
                        msg = json.loads(raw["data"])
                        user_id = int(msg.get("user_id", 0))
                        event = msg.get("event", "")
                        data = msg.get("data", {})
                    except (json.JSONDecodeError, ValueError, TypeError) as e:
                        logger.warning(f"[WS] pubsub invalid msg: {e}")
                        continue

                    # 只处理本实例连接的用户
                    await self._send_ws(user_id, {"type": "event", "event": event, "data": data})

            except asyncio.CancelledError:
                logger.info("[WS] pubsub loop cancelled")
                break
            except Exception as e:
                logger.warning(f"[WS] pubsub loop error: {e}, retry in {delay}s")
                await asyncio.sleep(delay)
                delay = min(delay * 2, 30)

        # 清理
        if self._pubsub:
            try:
                await self._pubsub.unsubscribe(_WS_BROADCAST_CHANNEL)
                await self._pubsub.close()
            except Exception:
                pass
            self._pubsub = None

    async def stop_pubsub(self) -> None:
        """停止 Pub/Sub 监听（进程退出时调用）。"""
        self._pubsub_running = False
        if self._pubsub_task:
            self._pubsub_task.cancel()
            try:
                await self._pubsub_task
            except asyncio.CancelledError:
                pass


# ===== 全局单例 =====

_manager: ConnectionManager | None = None


def get_manager() -> ConnectionManager:
    global _manager
    if _manager is None:
        _manager = ConnectionManager()
    return _manager


# ===== Watchdog Leader Election =====

async def try_acquire_watchdog_leader() -> bool:
    """尝试成为 watchdog leader。

    使用 SET NX EX 保证只有一个 worker 成功。
    成功返回 True（获得 leader），失败返回 False（当前是 follower）。
    """
    try:
        redis = await get_redis()
        ok = await redis.set(_WATCHDOG_LEADER_KEY, os.getpid(), nx=True, ex=_WATCHDOG_LEADER_TTL)
        return bool(ok)
    except Exception as e:
        logger.warning(f"[WS] watchdog leader acquire failed: {e}")
        return False


async def refresh_watchdog_leader() -> bool:
    """续期 watchdog leader（仅 leader 调用）。"""
    try:
        redis = await get_redis()
        pid = await redis.get(_WATCHDOG_LEADER_KEY)
        if pid and int(pid) == os.getpid():
            await redis.expire(_WATCHDOG_LEADER_KEY, _WATCHDOG_LEADER_TTL)
            return True
        return False
    except Exception as e:
        logger.warning(f"[WS] watchdog leader refresh failed: {e}")
        return False


async def is_watchdog_leader() -> bool:
    """检查当前进程是否为 watchdog leader。"""
    try:
        redis = await get_redis()
        pid = await redis.get(_WATCHDOG_LEADER_KEY)
        return pid and int(pid) == os.getpid()
    except Exception:
        return False
