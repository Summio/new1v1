from fastapi import APIRouter

from .system_config import router

system_config_router = APIRouter()
system_config_router.include_router(router, tags=["系统配置"])

__all__ = ["system_config_router"]
