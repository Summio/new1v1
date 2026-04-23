from typing import Optional

import jwt
from fastapi import Depends, Header, HTTPException, Request

from app.core.ctx import CTX_USER_ID
from app.models import Api, User
from app.settings import settings


class AuthControl:
    @classmethod
    async def is_authed(cls, token: str = Header(..., description="token验证")) -> Optional["User"]:
        try:
            decode_data = jwt.decode(token, settings.SECRET_KEY, algorithms=settings.JWT_ALGORITHM)
            user_id = decode_data.get("user_id")
            user = await User.filter(id=user_id).first()
            if not user:
                raise HTTPException(status_code=401, detail="Authentication failed")
            CTX_USER_ID.set(int(user_id))
            return user
        except jwt.DecodeError:
            raise HTTPException(status_code=401, detail="无效的Token")
        except jwt.ExpiredSignatureError:
            raise HTTPException(status_code=401, detail="登录已过期")
        except Exception:
            # 隐藏内部错误细节，防止信息泄漏
            raise HTTPException(status_code=500, detail="认证服务异常")


class PermissionControl:
    """权限检查，支持 Redis 缓存。"""

    # 权限缓存 TTL：5分钟
    PERM_CACHE_TTL = 300

    @classmethod
    async def has_permission(cls, request: Request, current_user: User = Depends(AuthControl.is_authed)) -> None:
        if current_user.is_superuser:
            return
        method = request.method
        path = request.url.path
        role_ids = await current_user.roles.all().values_list("id", flat=True)
        if not role_ids:
            raise HTTPException(status_code=403, detail="The user is not bound to a role")

        perm_key = f"perm:{current_user.id}"
        deny_key = f"perm_denied:{current_user.id}"
        perm_value = f"{method}:{path}"

        # 快速路径：先检查缓存中是否有"拒绝"标记
        try:
            redis_client = await get_redis()
            is_denied = await redis_client.sismember(deny_key, perm_value)
            if is_denied:
                raise HTTPException(status_code=403, detail=f"Permission denied method:{method} path:{path}")
            is_allowed = await redis_client.sismember(perm_key, perm_value)
            if is_allowed:
                return  # 有权限（缓存命中）
        except HTTPException:
            raise
        except Exception:
            # Redis 失败时降级到数据库查询
            pass

        # 数据库查询（缓存未命中或 Redis 不可用）
        has_perm = await Api.filter(
            role_apis__id__in=role_ids,
            method=method,
            path=path,
        ).exists()

        # 更新缓存（允许/拒绝都记录，避免重复查询数据库）
        try:
            redis_client = await get_redis()
            if has_perm:
                await redis_client.sadd(perm_key, perm_value)
                await redis_client.expire(perm_key, cls.PERM_CACHE_TTL)
            else:
                await redis_client.sadd(deny_key, perm_value)
                await redis_client.expire(deny_key, cls.PERM_CACHE_TTL)
        except Exception:
            # Redis 失败时静默忽略
            pass

        if not has_perm:
            raise HTTPException(status_code=403, detail=f"Permission denied method:{method} path:{path}")


DependAuth = Depends(AuthControl.is_authed)
DependPermission = Depends(PermissionControl.has_permission)


# ===== 限流依赖 =====
from app.core.redis import get_redis, rate_limit


def get_client_ip(request: Request) -> str:
    """获取真实客户端 IP。

    仅当请求来自可信代理列表时才读取 X-Forwarded-For 头，
    防止攻击者伪造 IP 绕过限流。
    """
    from app.settings.config import settings

    # 只有来自可信代理的请求才信任 X-Forwarded-For
    client_host = request.client.host if request.client else None
    if client_host and settings.TRUSTED_PROXY_IPS and client_host in settings.TRUSTED_PROXY_IPS:
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            return forwarded.split(",")[0].strip()
    return client_host or "unknown"


class RateLimit:
    """基于 Redis 的请求限流 FastAPI 依赖。"""

    def __init__(self, limit: int, window_seconds: int, key_prefix: str = "ratelimit"):
        self.limit = limit
        self.window = window_seconds
        self.key_prefix = key_prefix

    async def __call__(self, request: Request):
        from fastapi import HTTPException

        ip = get_client_ip(request)
        key = f"{self.key_prefix}:{ip}"
        try:
            redis_client = await get_redis()
            passed = await rate_limit(redis_client, key, self.limit, self.window)
            if not passed:
                raise HTTPException(
                    status_code=429,
                    detail=f"请求过于频繁，请 {self.window} 秒后再试",
                )
        except HTTPException:
            # 限流触发的 HTTPException 正常上抛
            raise
        except Exception:
            # Redis 连接失败时优雅降级：放行请求，避免阻断业务
            pass


# 常用限流实例（可按需调整参数）
LimitLogin = RateLimit(limit=10, window_seconds=60, key_prefix="limit:login")       # 登录：每分钟10次
LimitRegister = RateLimit(limit=5, window_seconds=300, key_prefix="limit:register")   # 注册：每5分钟5次
LimitHeartbeat = RateLimit(limit=20, window_seconds=60, key_prefix="limit:heartbeat")  # 心跳：每分钟20次
LimitCallback = RateLimit(limit=10, window_seconds=60, key_prefix="limit:callback")    # 支付回调：每分钟10次
