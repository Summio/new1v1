import json

from fastapi import APIRouter, HTTPException

from app.models.system_config import SYSTEM_CONFIG_CACHE_KEY, SystemConfig
from app.schemas.base import Success
from app.schemas.system import CertifiedCallPriceConfigIn
from app.services.certification_price_service import (
    CERTIFIED_CALL_PRICE_TIERS_KEY,
    DEFAULT_CERTIFIED_CALL_PRICE_TIERS,
    parse_certified_call_price_tiers,
)

router = APIRouter()


@router.get("", summary="获取认证用户通话价格档位")
async def get_certified_call_price_config():
    config_value = await SystemConfig.get_value(
        CERTIFIED_CALL_PRICE_TIERS_KEY,
        json.dumps(DEFAULT_CERTIFIED_CALL_PRICE_TIERS, ensure_ascii=False),
    )
    return Success(data={"tiers": parse_certified_call_price_tiers(config_value)})


@router.put("", summary="更新认证用户通话价格档位")
async def update_certified_call_price_config(config_in: CertifiedCallPriceConfigIn):
    tiers = sorted(set(config_in.tiers))
    if 0 not in tiers:
        tiers.insert(0, 0)
    try:
        cfg_value = json.dumps(tiers, ensure_ascii=False)
        config_obj = await SystemConfig.filter(cfg_key=CERTIFIED_CALL_PRICE_TIERS_KEY).first()
        if config_obj:
            config_obj.cfg_value = cfg_value
            await config_obj.save()
        else:
            await SystemConfig.create(
                cfg_key=CERTIFIED_CALL_PRICE_TIERS_KEY,
                cfg_value=cfg_value,
                description="认证用户通话价格档位",
            )
        from app.core.redis import get_redis

        redis = await get_redis()
        await redis.delete(SYSTEM_CONFIG_CACHE_KEY)
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail="配置更新失败") from exc
    return Success(msg="配置已更新")
