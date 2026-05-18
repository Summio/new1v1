from fastapi import APIRouter, Depends

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID
from app.core.dependency import LimitCallback
from app.schemas.app_api import VipOrderCreateIn, VipOrderCreateOut
from app.schemas.base import Fail, Success
from app.services.vip_service import (
    create_vip_order,
    dump_vip_package,
    load_vip_packages,
    mark_vip_order_paid,
)
from app.settings.config import settings

router = APIRouter()


@router.get("/vip/packages", summary="获取VIP套餐", dependencies=[Depends(DependAppAuth)])
async def vip_packages():
    packages = await load_vip_packages()
    return Success(data={"packages": [dump_vip_package(item) for item in packages]})


@router.post("/vip/order/create", summary="创建VIP订单", dependencies=[Depends(DependAppAuth)])
async def vip_order_create(req_in: VipOrderCreateIn):
    user_id = int(CTX_APP_USER_ID.get() or 0)
    if user_id <= 0:
        return Fail(code=401, msg="用户不存在")
    try:
        order = await create_vip_order(
            user_id=user_id,
            package_index=req_in.package_index,
            pay_channel=req_in.pay_channel,
        )
    except ValueError as exc:
        return Fail(code=400, msg=str(exc))
    except RuntimeError as exc:
        return Fail(code=500, msg=str(exc))

    pay_url = None
    if order.pay_channel == "wx":
        pay_url = f"https://api.mch.weixin.qq.com/pay/unifiedorder?out_trade_no={order.order_no}"
    elif order.pay_channel == "alipay":
        pay_url = f"https://openapi.alipay.com/gateway.do?out_trade_no={order.order_no}"
    return Success(
        data=VipOrderCreateOut(
            order_no=order.order_no,
            pay_url=pay_url,
            amount=int(order.amount),
            duration_days=int(order.duration_days),
            vip_expires_at=order.after_vip_expires_at,
        ).model_dump(mode="json")
    )


@router.post(
    "/vip/order/callback", summary="VIP订单支付回调", dependencies=[Depends(DependAppAuth), Depends(LimitCallback)]
)
async def vip_order_callback(order_no: str):
    """VIP 支付回调。

    当前真实支付网关尚未接入，此接口仅在 Mock 回调开关开启时用于标记支付成功。
    """
    if not settings.ENABLE_MOCK_CALLBACK:
        return Fail(code=503, msg="VIP支付回调接口未开放，请使用真实支付渠道")
    user_id = int(CTX_APP_USER_ID.get() or 0)
    if user_id <= 0:
        return Fail(code=401, msg="用户不存在")
    try:
        order = await mark_vip_order_paid(order_no, user_id=user_id)
    except ValueError as exc:
        return Fail(code=404, msg=str(exc))
    return Success(
        data={
            "msg": "VIP开通成功",
            "vip_expires_at": order.after_vip_expires_at.isoformat() if order.after_vip_expires_at else None,
        }
    )
