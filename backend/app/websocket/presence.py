"""WebSocket 在线状态管理。

基于 Redis + WebSocket 连接状态的统一在线状态系统。

设计原则：
  - 用户打开 App（WS 连接）= 在线
  - 用户离开 App（WS 断开）= 离线
  - 用户可手动切换在线状态（"离线"仅影响业务判断，不断开 WS 连接）
  - 在线状态变化通过 WebSocket 广播给所有在线用户

Redis 键：
  ws:online                    - SET，所有在线用户 ID（WS 连接时 sadd，断开时 srem）
  ws:manual_offline:{user_id}  - STRING，手动离线标记（设值=离线，清除=恢复在线）

is_online(user_id) 逻辑：
  return sismember("ws:online", user_id)
         AND NOT exists("ws:manual_offline:{user_id}")
"""

from __future__ import annotations

import asyncio
from typing import TYPE_CHECKING

from app.core.redis import get_redis

if TYPE_CHECKING:
    from app.websocket.manager import ConnectionManager

_WS_ONLINE_KEY = "ws:online"
_MANUAL_OFFLINE_KEY_PREFIX = "ws:manual_offline:"
_MANUAL_OFFLINE_TTL = 24 * 60 * 60  # 24 小时，手动离线状态超时自动清除


async def is_online(user_id: int) -> bool:
    """判断用户是否在线（WS 已连接 且 未手动离线）。"""
    redis = await get_redis()
    connected = await redis.sismember(_WS_ONLINE_KEY, user_id)
    if not connected:
        return False
    offline = await redis.exists(f"{_MANUAL_OFFLINE_KEY_PREFIX}{user_id}")
    return not bool(offline)


async def set_manual_offline(user_id: int) -> None:
    """标记用户手动离线。保持 WS 连接，不断开。"""
    redis = await get_redis()
    await redis.setex(
        f"{_MANUAL_OFFLINE_KEY_PREFIX}{user_id}",
        _MANUAL_OFFLINE_TTL,
        "1",
    )


async def clear_manual_offline(user_id: int) -> None:
    """清除手动离线标记，用户恢复在线。"""
    redis = await get_redis()
    await redis.delete(f"{_MANUAL_OFFLINE_KEY_PREFIX}{user_id}")


async def broadcast_presence(
    manager: ConnectionManager,
    user_id: int,
    online: bool,
) -> None:
    """广播用户在线状态变化给所有在线用户。"""
    from app.websocket.events import push_presence

    asyncio.create_task(
        push_presence(user_id=int(user_id), online=bool(online)),
    )


async def get_online_user_ids() -> set[int]:
    """获取所有在线用户 ID 集合（ws:online SET）。"""
    redis = await get_redis()
    members = await redis.smembers(_WS_ONLINE_KEY)
    return {int(m) for m in members}
