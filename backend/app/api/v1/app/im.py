import time

from fastapi import APIRouter

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID
from app.log import logger
from app.schemas.app_api import IMSigOut
from app.schemas.base import Fail, Success

router = APIRouter()
USER_SIG_EXPIRE_SECONDS = 3600 * 2


@router.get("/im/usersig", summary="获取IM UserSig", dependencies=[DependAppAuth])
async def get_usersig():
    """
    获取腾讯云 IM 的 UserSig。
    使用 TLSSigAPIv2 生成真实签名。
    """
    from app.models.system_config import SystemConfig

    user_id = CTX_APP_USER_ID.get()
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
