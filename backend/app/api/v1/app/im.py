import time

from fastapi import APIRouter

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID
from app.schemas.app_api import IMSigOut
from app.schemas.base import Fail, Success

router = APIRouter()


@router.get("/im/usersig", summary="获取IM UserSig", dependencies=[DependAppAuth])
async def get_usersig():
    """
    获取腾讯云 IM 的 UserSig。
    使用 TLSSigAPIv2 生成真实签名。
    """
    from app.settings.config import im_settings

    user_id = CTX_APP_USER_ID.get()

    # 检查 IM 配置
    if not im_settings or not im_settings.is_configured:
        return Fail(msg="IM 配置未完成，请联系管理员配置 IM_SDKAPPID 和 IM_SECRETKEY")

    try:
        # 使用腾讯云签名库
        from tencentcloud.imsig.v2 import TLSSigAPIv2

        api = TLSSigAPIv2(im_settings.IM_SDKAPPID, im_settings.IM_SECRETKEY)
        usersig = api.generate_user_sig(
            userid=f"huanxi_{user_id}",
            expire=3600 * 24 * 7  # 7天有效期
        )
        expired_time = int(time.time()) + 3600 * 24 * 7

        return Success(
            data=IMSigOut(
                usersig=usersig,
                expired_time=expired_time,
            ).model_dump()
        )
    except Exception as e:
        return Fail(msg=f"UserSig 生成失败: {str(e)}")