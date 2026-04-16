from fastapi import APIRouter

from app.schemas.base import Success

router = APIRouter()


@router.get("/init/bootstrap", summary="获取 App 初始化配置")
async def get_app_bootstrap():
    from app.models.system_config import SystemConfig

    cfgs = await SystemConfig.all()
    config_map = {cfg.cfg_key: cfg.cfg_value for cfg in cfgs}

    coin_name = config_map.get("coin_name") or "金币"
    diamond_name = config_map.get("diamond_name") or "钻石"
    call_reject_inbound_protect_seconds_raw = (
        config_map.get("call_reject_inbound_protect_seconds") or "5"
    ).strip()
    call_reject_pair_protect_seconds_raw = (
        config_map.get("call_reject_pair_protect_seconds") or "5"
    ).strip()

    im_sdk_app_id_raw = (config_map.get("im_sdk_app_id") or "").strip()
    im_secret_key = (config_map.get("im_secret_key") or "").strip()
    rtc_app_id = (config_map.get("rtc_app_id") or "").strip()
    rtc_app_certificate = (config_map.get("rtc_app_certificate") or "").strip()
    try:
        im_sdk_app_id = int(im_sdk_app_id_raw) if im_sdk_app_id_raw else None
    except ValueError:
        im_sdk_app_id = None
    is_im_configured = bool(im_sdk_app_id and im_secret_key)
    is_rtc_configured = bool(rtc_app_id and rtc_app_certificate)
    try:
        call_reject_inbound_protect_seconds = int(call_reject_inbound_protect_seconds_raw)
    except ValueError:
        call_reject_inbound_protect_seconds = 5
    if call_reject_inbound_protect_seconds < 0:
        call_reject_inbound_protect_seconds = 0

    try:
        call_reject_pair_protect_seconds = int(call_reject_pair_protect_seconds_raw)
    except ValueError:
        call_reject_pair_protect_seconds = 5
    if call_reject_pair_protect_seconds < 0:
        call_reject_pair_protect_seconds = 0

    return Success(
        data={
            "token_names": {
                "coin_name": coin_name,
                "diamond_name": diamond_name,
            },
            "im": {
                "configured": is_im_configured,
                "sdk_app_id": im_sdk_app_id,
            },
            "rtc": {
                "configured": is_rtc_configured,
            },
            "call": {
                "reject_inbound_protect_seconds": call_reject_inbound_protect_seconds,
                "reject_pair_protect_seconds": call_reject_pair_protect_seconds,
            },
        }
    )
