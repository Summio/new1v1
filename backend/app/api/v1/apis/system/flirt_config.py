import logging

from fastapi import APIRouter, HTTPException

from app.core.redis import get_redis
from app.models.system_config import SYSTEM_CONFIG_CACHE_KEY, SystemConfig
from app.schemas.base import Success
from app.schemas.system import FlirtConfigIn
from app.utils.parse import safe_parse_bool, safe_parse_int

logger = logging.getLogger(__name__)

router = APIRouter()

FLIRT_FILTER_SAME_GENDER_KEY = "flirt_filter_same_gender_enabled"
FLIRT_FILTER_CERTIFIED_USER_KEY = "flirt_filter_certified_user_enabled"
FLIRT_GREET_DAILY_LIMIT_KEY = "flirt_greet_daily_limit"
FLIRT_GREET_COOLDOWN_SECONDS_KEY = "flirt_greet_cooldown_seconds"


async def _load_flirt_config() -> FlirtConfigIn:
    same_gender_raw = await SystemConfig.get_value(FLIRT_FILTER_SAME_GENDER_KEY, "true")
    certified_user_raw = await SystemConfig.get_value(FLIRT_FILTER_CERTIFIED_USER_KEY, "true")
    greet_daily_limit_raw = await SystemConfig.get_value(FLIRT_GREET_DAILY_LIMIT_KEY, "3")
    greet_cooldown_seconds_raw = await SystemConfig.get_value(FLIRT_GREET_COOLDOWN_SECONDS_KEY, "10")
    return FlirtConfigIn(
        filter_same_gender_enabled=safe_parse_bool(same_gender_raw, True),
        filter_certified_user_enabled=safe_parse_bool(certified_user_raw, True),
        greet_daily_limit=max(0, min(20, safe_parse_int(greet_daily_limit_raw, 3))),
        greet_cooldown_seconds=max(0, min(3600, safe_parse_int(greet_cooldown_seconds_raw, 10))),
    )


@router.get("", summary="获取搭讪配置")
async def get_flirt_config():
    config = await _load_flirt_config()
    return Success(data=config.model_dump())


@router.put("", summary="更新搭讪配置")
async def update_flirt_config(config_in: FlirtConfigIn):
    try:
        values = {
            FLIRT_FILTER_SAME_GENDER_KEY: (
                str(bool(config_in.filter_same_gender_enabled)).lower(),
                "搭讪配置-过滤同性别",
            ),
            FLIRT_FILTER_CERTIFIED_USER_KEY: (
                str(bool(config_in.filter_certified_user_enabled)).lower(),
                "搭讪配置-过滤真人认证用户",
            ),
            FLIRT_GREET_DAILY_LIMIT_KEY: (
                str(int(config_in.greet_daily_limit)),
                "搭讪配置-每日打招呼次数",
            ),
            FLIRT_GREET_COOLDOWN_SECONDS_KEY: (
                str(int(config_in.greet_cooldown_seconds)),
                "搭讪配置-打招呼冷却时间",
            ),
        }
        for cfg_key, (cfg_value, description) in values.items():
            config_obj = await SystemConfig.filter(cfg_key=cfg_key).first()
            if config_obj:
                config_obj.cfg_value = cfg_value
                config_obj.description = description
                await config_obj.save(update_fields=["cfg_value", "description"])
            else:
                await SystemConfig.create(
                    cfg_key=cfg_key,
                    cfg_value=cfg_value,
                    description=description,
                )

        try:
            redis = await get_redis()
            await redis.delete(SYSTEM_CONFIG_CACHE_KEY)
        except Exception as e:
            logger.warning(f"Failed to clear cache: {e}")

        return Success(msg="配置已更新")
    except Exception as e:
        logger.error(f"Failed to update flirt config: {e}")
        raise HTTPException(status_code=500, detail="配置更新失败")
