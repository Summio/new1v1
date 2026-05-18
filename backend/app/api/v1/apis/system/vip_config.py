import json
import logging

from fastapi import APIRouter, HTTPException

from app.core.redis import get_redis
from app.models.system_config import SYSTEM_CONFIG_CACHE_KEY, SystemConfig
from app.schemas.base import Success
from app.schemas.system import VipConfigIn
from app.services.vip_service import (
    VIP_PACKAGES_KEY,
    dump_vip_package,
    load_vip_packages,
)

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("", summary="获取VIP配置")
async def get_vip_config():
    packages = await load_vip_packages()
    return Success(data={"packages": [dump_vip_package(item) for item in packages]})


@router.put("", summary="更新VIP配置")
async def update_vip_config(config_in: VipConfigIn):
    try:
        packages_json = json.dumps([dump_vip_package(item) for item in config_in.packages], ensure_ascii=False)
        config_obj = await SystemConfig.filter(cfg_key=VIP_PACKAGES_KEY).first()
        if config_obj:
            config_obj.cfg_value = packages_json
            config_obj.description = "VIP套餐配置"
            await config_obj.save(update_fields=["cfg_value", "description"])
        else:
            await SystemConfig.create(cfg_key=VIP_PACKAGES_KEY, cfg_value=packages_json, description="VIP套餐配置")
        try:
            redis = await get_redis()
            await redis.delete(SYSTEM_CONFIG_CACHE_KEY)
        except Exception as exc:  # noqa: BLE001
            logger.warning("Failed to clear system config cache: %s", exc)
    except Exception as exc:
        logger.exception("Failed to update vip config: %s", exc)
        raise HTTPException(status_code=500, detail="配置更新失败") from exc
    return Success(msg="配置已更新")
