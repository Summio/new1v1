from typing import Optional

import jwt
from fastapi import Depends, Header, HTTPException, Request

from app.core.ctx import CTX_USER_ID
from app.models import Api, Role, User
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
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"{repr(e)}")


class PermissionControl:
    @classmethod
    async def has_permission(cls, request: Request, current_user: User = Depends(AuthControl.is_authed)) -> None:
        if current_user.is_superuser:
            return
        method = request.method
        path = request.url.path
        # 优化：一次性加载所有角色的所有 API，避免 N+1 查询
        roles: list[Role] = await current_user.roles.all().prefetch_related("apis")
        if not roles:
            raise HTTPException(status_code=403, detail="The user is not bound to a role")
        # 收集所有 API id
        api_ids: set[int] = set()
        for role in roles:
            async for api in role.apis.all():
                api_ids.add(api.id)
        # 一次性查询所有需要的 API
        apis = await Api.filter(id__in=api_ids).all()
        permission_apis = set((api.method, api.path) for api in apis)
        if (method, path) not in permission_apis:
            raise HTTPException(status_code=403, detail=f"Permission denied method:{method} path:{path}")


DependAuth = Depends(AuthControl.is_authed)
DependAdminAuth = Depends(AuthControl.is_authed)
DependPermission = Depends(PermissionControl.has_permission)


# ===== 限流依赖 =====
from starlette.requests import Request
from starlette.responses import JSONResponse

from app.core.redis import get_redis, rate_limit


def get_client_ip(request: Request) -> str:
    """从请求中获取客户端 IP，优先取 X-Forwarded-For 头。"""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


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
