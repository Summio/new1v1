from fastapi import APIRouter, HTTPException

from app.core.redis import get_redis
from app.models.system_config import SYSTEM_CONFIG_CACHE_KEY, SystemConfig
from app.schemas.base import Success
from app.schemas.system import IMTextBillingConfigIn
from app.services.im_text_billing_service import (
    dump_im_text_billing_config,
    parse_im_text_billing_config,
)

router = APIRouter()

CONFIG_ITEMS = {
    "im_text_message_billing_enabled": "文字聊天扣费开关",
    "im_text_message_price": "文字聊天每条扣费金币数",
    "im_text_message_anchor_share_bps": "文字聊天主播分成比例",
}


@router.get("", summary="获取文字聊天计费配置")
async def get_im_text_billing_config():
    config_map = await SystemConfig.get_all_as_dict()
    config = parse_im_text_billing_config(config_map)
    return Success(data=dump_im_text_billing_config(config))


@router.put("", summary="更新文字聊天计费配置")
async def update_im_text_billing_config(config_in: IMTextBillingConfigIn):
    values = {
        "im_text_message_billing_enabled": "true" if config_in.enabled else "false",
        "im_text_message_price": str(config_in.price),
        "im_text_message_anchor_share_bps": str(config_in.anchor_share_bps),
    }
    try:
        for key, value in values.items():
            obj = await SystemConfig.filter(cfg_key=key).first()
            if obj:
                obj.cfg_value = value
                obj.description = CONFIG_ITEMS[key]
                await obj.save(update_fields=["cfg_value", "description"])
            else:
                await SystemConfig.create(
                    cfg_key=key,
                    cfg_value=value,
                    description=CONFIG_ITEMS[key],
                )
        redis = await get_redis()
        await redis.delete(SYSTEM_CONFIG_CACHE_KEY)
    except Exception as exc:
        raise HTTPException(status_code=500, detail="配置更新失败") from exc
    return Success(msg="配置已更新")
