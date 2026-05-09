from fastapi import APIRouter

from .certified_call_price_config import router as certified_call_price_config_router
from .im_text_billing_config import router as im_text_billing_config_router
from .recharge_config import router as recharge_config_router
from .withdraw_config import router as withdraw_config_router

system_router = APIRouter()
system_router.include_router(recharge_config_router, prefix="/recharge-config", tags=["系统配置-充值"])
system_router.include_router(withdraw_config_router, prefix="/withdraw-config", tags=["系统配置-提现"])
system_router.include_router(
    im_text_billing_config_router,
    prefix="/im-text-billing-config",
    tags=["系统配置-文字聊天计费"],
)
system_router.include_router(
    certified_call_price_config_router,
    prefix="/certified-call-price-config",
    tags=["系统配置-认证用户通话价格"],
)
