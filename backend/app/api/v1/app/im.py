import time

from fastapi import APIRouter, Depends, Query

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID
from app.log import logger
from app.models import AppUser
from app.schemas.app_api import IMSigOut, IMTextChargeIn, IMTextChargeOut
from app.schemas.base import Fail, Success
from app.services.customer_service import load_customer_service_config
from app.services.im_text_billing_service import (
    IMTextBillingError,
    charge_im_text_message,
)
from app.services.interaction_relation_service import (
    InteractionRelationError,
    ensure_interaction_allowed,
)
from app.services.user_block_service import UserBlockError, ensure_not_blocked

router = APIRouter()
USER_SIG_EXPIRE_SECONDS = 3600 * 2


@router.get("/im/usersig", summary="获取IM UserSig", dependencies=[Depends(DependAppAuth)])
async def get_usersig(
    peer_user_id: int | None = Query(default=None, description="目标聊天用户ID"),
):
    """
    获取腾讯云 IM 的 UserSig。
    使用 TLSSigAPIv2 生成真实签名。
    """
    from app.models.system_config import SystemConfig

    user_id = CTX_APP_USER_ID.get()
    if peer_user_id is not None and int(peer_user_id) == int(user_id):
        return Fail(code=400, msg="不能和自己聊天")

    config_map = await SystemConfig.get_all_as_dict()
    sdk_app_id_raw = (config_map.get("im_sdk_app_id") or "").strip()
    secret_key = (config_map.get("im_secret_key") or "").strip()
    try:
        sdk_app_id = int(sdk_app_id_raw) if sdk_app_id_raw else None
    except ValueError:
        sdk_app_id = None

    # 检查 IM 配置
    if not sdk_app_id or not secret_key:
        logger.error("IM usersig failed: IM settings not configured in system_config")
        return Fail(msg="IM 配置未完成，请在系统配置中设置 im_sdk_app_id 和 im_secret_key")

    try:
        # 使用腾讯云签名库
        from TLSSigAPIv2 import TLSSigAPIv2

        api = TLSSigAPIv2(sdk_app_id, secret_key)
        usersig = api.gen_sig(
            identifier=f"chat_{user_id}",
            expire=USER_SIG_EXPIRE_SECONDS,
        )
        expired_time = int(time.time()) + USER_SIG_EXPIRE_SECONDS

        return Success(
            data=IMSigOut(
                usersig=usersig,
                expired_time=expired_time,
                sdk_app_id=sdk_app_id,
            ).model_dump()
        )
    except Exception as e:
        logger.exception("IM usersig generation error: {}", str(e))
        return Fail(msg="UserSig 生成失败，请稍后重试")


@router.post("/im/text-charge", summary="文字消息发送前扣费", dependencies=[Depends(DependAppAuth)])
async def charge_text_message(req_in: IMTextChargeIn):
    sender_id = CTX_APP_USER_ID.get()
    sender = await AppUser.filter(id=sender_id, status="normal").first()
    if not sender:
        return Fail(code=401, msg="登录状态异常")
    receiver = await AppUser.filter(id=req_in.receiver_user_id, status="normal").first()
    if not receiver:
        return Fail(code=404, msg="目标用户不存在或状态异常")
    customer_service = await load_customer_service_config()
    is_customer_service_sender = customer_service.user_id == int(sender_id)
    if bool(receiver.text_dnd_enabled) and not is_customer_service_sender:
        return Fail(code=403, msg="对方已开启文字勿扰")
    try:
        await ensure_not_blocked(int(sender_id), int(receiver.id), "聊天")
        await ensure_interaction_allowed(action="im_text", actor=sender, target=receiver)
    except UserBlockError as exc:
        return Fail(code=exc.code, msg=exc.message)
    except InteractionRelationError as exc:
        return Fail(code=exc.code, msg=exc.message)
    try:
        result = await charge_im_text_message(
            sender_id=int(sender_id),
            receiver_user_id=int(req_in.receiver_user_id),
            request_id=req_in.request_id.strip(),
        )
    except IMTextBillingError as exc:
        return Fail(code=exc.code, msg=exc.message)
    return Success(data=IMTextChargeOut(**result.__dict__).model_dump())
