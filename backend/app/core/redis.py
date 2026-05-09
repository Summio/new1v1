import json
from typing import Any, Optional

import redis.asyncio as redis

from app.settings.config import settings

_redis_client: Optional[redis.Redis] = None


async def get_redis() -> redis.Redis:
    global _redis_client
    if _redis_client is None:
        _redis_client = redis.Redis(
            host=settings.REDIS_HOST,
            port=settings.REDIS_PORT,
            db=settings.REDIS_DB,
            password=settings.REDIS_PASSWORD or None,
            decode_responses=True,
        )
    return _redis_client


async def close_redis():
    global _redis_client
    if _redis_client:
        await _redis_client.close()
        _redis_client = None


class RedisCache:
    """Redis 缓存封装"""

    def __init__(self, client: redis.Redis):
        self.client = client

    async def set(self, key: str, value: Any, expire: int = 0) -> bool:
        """设置值，统一使用 JSON 序列化，expire=0 表示永不过期"""
        v = json.dumps(value, ensure_ascii=False)
        if expire > 0:
            return await self.client.setex(key, expire, v)
        return await self.client.set(key, v)

    async def get(self, key: str) -> Optional[str]:
        return await self.client.get(key)

    async def get_json(self, key: str) -> Optional[Any]:
        v = await self.client.get(key)
        if v is None:
            return None
        try:
            return json.loads(v)
        except (json.JSONDecodeError, TypeError):
            return v

    async def delete(self, key: str) -> int:
        return await self.client.delete(key)

    async def incr(self, key: str, amount: int = 1) -> int:
        return await self.client.incrby(key, amount)

    async def expire(self, key: str, seconds: int) -> bool:
        return await self.client.expire(key, seconds)


# ===== App 业务场景 Redis Key 规范 =====
def call_balance_key(user_id: int) -> str:
    """通话预扣费余额 key"""
    return f"call:balance:{user_id}"


def call_session_key(caller_id: int, callee_id: int) -> str:
    """通话会话 key"""
    return f"call:session:{caller_id}:{callee_id}"


def heartbeat_key(call_id: int) -> str:
    """心跳 key（5秒 TTL，自动过期 = 掉线检测）"""
    return f"call:heartbeat:{call_id}"


def online_anchors_key() -> str:
    """在线认证用户集合 key"""
    return "anchor:online"


# ===== 限流工具 =====
# Lua 脚本保证 INCR + EXPIRE 原子性，防止并发请求绕过限流
_RATELIMIT_LUA_SCRIPT = """
local count = redis.call('INCR', KEYS[1])
if count == 1 then
    redis.call('EXPIRE', KEYS[1], ARGV[1])
end
return count
"""
_ratelimit_sha: str | None = None


async def _get_ratelimit_sha(client: redis.Redis) -> str:
    """缓存 Lua 脚本的 SHA，避免每次执行都发送脚本源码。"""
    global _ratelimit_sha
    if _ratelimit_sha is None:
        _ratelimit_sha = await client.script_load(_RATELIMIT_LUA_SCRIPT)
    return _ratelimit_sha


async def rate_limit(client: redis.Redis, key: str, limit: int, window_seconds: int) -> bool:
    """Redis 原子滑动窗口限流。返回 True = 通过，False = 被限流。"""
    window_key = f"{key}:{int(__import__('time').time() // window_seconds)}"
    try:
        sha = await _get_ratelimit_sha(client)
        count = await client.evalsha(sha, 1, window_key, window_seconds)
    except redis.ResponseError:
        # Lua 脚本未加载（Redis 重启后），回退到普通方式
        count = await client.incr(window_key)
        if count == 1:
            await client.expire(window_key, window_seconds + 1)
    return int(count) <= limit
