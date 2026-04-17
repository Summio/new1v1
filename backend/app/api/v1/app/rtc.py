import time

from fastapi import APIRouter

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID
from app.log import logger
from app.models import CallRecord
from app.schemas.app_api import RTCTokenIn, RTCTokenOut
from app.schemas.base import Fail, Success

router = APIRouter()
RTC_TOKEN_EXPIRE_SECONDS = 3600
DEFAULT_FREE_SECONDS_BEFORE_BILLING = 10
MAX_FREE_SECONDS_BEFORE_BILLING = 600


def _safe_parse_int(raw: str | None, default: int) -> int:
    if raw is None:
        return default
    try:
        return int(str(raw).strip())
    except (TypeError, ValueError):
        return default


@router.post("/rtc/token", summary="获取 RTC Token", dependencies=[DependAppAuth])
async def get_rtc_token(req_in: RTCTokenIn):
    from app.models.system_config import SystemConfig

    user_id = CTX_APP_USER_ID.get()
    call_record = await CallRecord.filter(id=req_in.call_id, status="ongoing").first()
    if not call_record:
        return Fail(code=404, msg="通话不存在或已结束")

    if user_id not in {int(call_record.caller_id), int(call_record.callee_id)}:
        return Fail(code=403, msg="无权加入该通话")

    config_map = await SystemConfig.get_all_as_dict()
    rtc_app_id = (config_map.get("rtc_app_id") or "").strip()
    rtc_app_certificate = (config_map.get("rtc_app_certificate") or "").strip()
    free_seconds_before_billing = _safe_parse_int(
        config_map.get("call_billing_free_seconds"),
        DEFAULT_FREE_SECONDS_BEFORE_BILLING,
    )
    if free_seconds_before_billing < 0:
        free_seconds_before_billing = 0
    if free_seconds_before_billing > MAX_FREE_SECONDS_BEFORE_BILLING:
        free_seconds_before_billing = MAX_FREE_SECONDS_BEFORE_BILLING
    if not rtc_app_id or not rtc_app_certificate:
        logger.error("RTC token failed: missing rtc_app_id or rtc_app_certificate")
        return Fail(msg="RTC 配置未完成，请在系统配置中设置 rtc_app_id 和 rtc_app_certificate")

    uid = int(user_id) & 0xFFFFFFFF
    if uid == 0:
        uid = 1
    channel = f"call_{call_record.id}"
    expired_time = int(time.time()) + RTC_TOKEN_EXPIRE_SECONDS

    try:
        from agora_token_builder import RtcTokenBuilder

        token = RtcTokenBuilder.buildTokenWithUid(
            rtc_app_id,
            rtc_app_certificate,
            channel,
            uid,
            1,
            expired_time,
        )
    except Exception as e:
        logger.exception("RTC token generation error: {}", str(e))
        return Fail(msg="RTC Token 生成失败，请稍后重试")

    return Success(
        data=RTCTokenOut(
            app_id=rtc_app_id,
            channel=channel,
            token=token,
            uid=uid,
            expired_time=expired_time,
            free_seconds_before_billing=free_seconds_before_billing,
        ).model_dump()
    )
