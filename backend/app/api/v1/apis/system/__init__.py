from fastapi import APIRouter

from .recharge_config import router as recharge_config_router

system_router = APIRouter()
system_router.include_router(recharge_config_router, prefix="/recharge-config", tags=["系统配置-充值"])
