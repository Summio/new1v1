from datetime import datetime, timedelta, timezone
import asyncio
import time
from typing import AsyncGenerator

from fastapi import HTTPException, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import ExpiredSignatureError, JWTError, jwt

from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.core.redis import get_redis
from app.models import AppUser
from app.settings.config import settings

ALGORITHM = "HS256"

# JWT 黑名单 key 前缀（被撤销的 token 存入 Redis）
TOKEN_BLACKLIST_PREFIX = "jwt:blacklist:"

# P3-C1 修复：使用 asyncio.Lock 替代 threading.Lock，避免阻塞事件循环
_BLACKLIST_CACHE: dict[str, tuple[bool, float]] = {}
_CACHE_TTL_SECONDS = 300  # 5 分钟
_CACHE_LOCK = asyncio.Lock()


async def _cache_get(token: str) -> bool | None:
    """C-2 修复：本地缓存查询，async-safe。返回 True=已确认不在黑名单，False=已确认在黑名单，None=未命中。"""
    async with _CACHE_LOCK:
        entry = _BLACKLIST_CACHE.get(token)
        if entry is None:
            return None
        is_valid, expire_at = entry
        if time.monotonic() > expire_at:
            del _BLACKLIST_CACHE[token]
            return None
        return is_valid


async def _cache_set(token: str, is_valid: bool) -> None:
    """写入本地缓存，async-safe。"""
    async with _CACHE_LOCK:
        _BLACKLIST_CACHE[token] = (is_valid, time.monotonic() + _CACHE_TTL_SECONDS)


async def _cache_invalidate(token: str) -> None:
    """C-2 修复：logout 时主动使本地缓存失效，避免 5 分钟窗口期内已撤销 token 仍被判定为有效。"""
    async with _CACHE_LOCK:
        _BLACKLIST_CACHE.pop(token, None)


async def is_token_valid(token: str) -> bool:
    """检查 JWT 是否在 Redis 黑名单中（已被撤销），带本地 TTL 缓存。"""
    cached = await _cache_get(token)
    if cached is not None:
        return cached

    try:
        redis = await get_redis()
        key = f"{TOKEN_BLACKLIST_PREFIX}{token}"
        exists = await redis.exists(key)
        is_valid = not bool(exists)
    except Exception:
        is_valid = True  # Redis 不可用时降级，放行

    await _cache_set(token, is_valid)
    return is_valid


async def is_app_authed(token: str) -> AppUser | None:
    """检查 JWT 有效性并返回对应 AppUser，找不到或已撤销时返回 None。"""
    payload = await decode_app_token(token)
    if not payload:
        return None
    if not await is_token_valid(token):
        return None
    user_id = int(payload["sub"])
    return await AppUser.filter(id=user_id).first()


def create_app_access_token(user_id: int, expires_delta: timedelta | None = None) -> str:
    """生成 App 用户 JWT access_token。"""
    default_expires = timedelta(minutes=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES)
    expire = datetime.now(timezone.utc) + (expires_delta or default_expires)
    payload = {"sub": str(user_id), "exp": expire}
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=ALGORITHM)


def create_app_refresh_token(user_id: int) -> str:
    """生成 App 用户 JWT refresh_token（有效期 30 天）。"""
    expire = datetime.now(timezone.utc) + timedelta(days=30)
    payload = {"sub": str(user_id), "type": "refresh", "exp": expire}
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=ALGORITHM)


async def decode_app_token(token: str) -> dict | None:
    """解析 App 用户 JWT，返回 payload dict 或 None。"""
    try:
        payload = jwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[ALGORITHM],
        )
        if payload.get("type") == "refresh":
            return None
        # 统一校验并归一化 sub，避免后续鉴权链路出现 KeyError/ValueError
        sub = payload.get("sub")
        try:
            payload["sub"] = str(int(sub))
        except (TypeError, ValueError):
            return None
        return payload
    except ExpiredSignatureError:
        return None
    except JWTError:
        return None


async def DependAppAuth(request: Request) -> AsyncGenerator[int, None]:
    """App 端 JWT 鉴权依赖。

    验证流程：
      1. 从 Authorization: Bearer <token> 提取 token
      2. 验证 JWT 签名和有效期
      3. 查询 AppUser 并设置到请求上下文
      4. 检查用户状态（禁用/封禁）
      5. 检查 token 是否在 Redis 黑名单中（已 logout 的 token 失效）
    """
    bearer = HTTPBearer(auto_error=True)
    credentials: HTTPAuthorizationCredentials = await bearer(request=request)
    token = credentials.credentials

    payload = await decode_app_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Token无效或已过期")

    # 黑名单检查：已 logout 的 token 拒绝访问
    if not await is_token_valid(token):
        raise HTTPException(status_code=401, detail="Token已失效，请重新登录")

    user_id = int(payload["sub"])
    app_user = await AppUser.filter(id=user_id).first()
    if not app_user:
        raise HTTPException(status_code=401, detail="用户不存在")

    # 账号状态校验
    if app_user.status == "banned":
        raise HTTPException(status_code=403, detail="账号已被封禁")
    if app_user.status == "disabled":
        raise HTTPException(status_code=403, detail="账号已禁用")

    user_id_token = CTX_APP_USER_ID.set(user_id)
    user_obj_token = CTX_APP_USER_OBJ.set(app_user)
    try:
        yield user_id
    finally:
        CTX_APP_USER_ID.reset(user_id_token)
        CTX_APP_USER_OBJ.reset(user_obj_token)


async def logout_app_user(token: str, expire_seconds: int | None = None) -> bool:
    """撤销指定 JWT：将 token 加入 Redis 黑名单。

    Args:
        token: 要撤销的 JWT 字符串
        expire_seconds: 黑名单有效期，不填则取 JWT 剩余有效期（上限 7 天）

    Returns:
        True 成功写入黑名单，False（Redis 不可用时）降级
    """
    try:
        redis = await get_redis()
        key = f"{TOKEN_BLACKLIST_PREFIX}{token}"

        # 计算 TTL：优先使用传入值，不超过 JWT 最大有效期（7 天）
        ttl = expire_seconds
        if ttl is None:
            payload = await decode_app_token(token)
            if payload:
                exp = payload.get("exp")
                if exp:
                    ttl = max(0, int(exp - datetime.now(timezone.utc).timestamp()))
                    ttl = min(ttl, 7 * 24 * 3600)

        if ttl and ttl > 0:
            await redis.setex(key, ttl, "revoked")
            # C-2 修复：logout 时主动使本地缓存失效
            await _cache_invalidate(token)
            return True
        return False
    except Exception:
        return False


class AppAuthControl:
    """App 鉴权控制类（向后兼容接口）。"""

    @staticmethod
    async def create_app_token(app_user: AppUser, expires_delta: timedelta | None = None) -> str:
        """为 AppUser 实例生成 access_token（向后兼容旧接口）。"""
        return create_app_access_token(int(app_user.id), expires_delta)

    @staticmethod
    async def is_app_authed(token: str) -> AppUser | None:
        """检查 JWT 有效性并返回对应 AppUser（向后兼容旧接口）。"""
        return await is_app_authed(token)
