import json
import logging

from fastapi import APIRouter, HTTPException

from app.core.redis import get_redis
from app.models.system_config import SYSTEM_CONFIG_CACHE_KEY, SystemConfig
from app.schemas.base import Success
from app.schemas.system import WithdrawConfigIn, WithdrawPackageItem

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("", summary="获取提现配置")
async def get_withdraw_config():
    """获取当前提现配置"""
    config_value = await SystemConfig.get_value("withdraw_packages", "[]")
    try:
        packages_data = json.loads(config_value)
        if not isinstance(packages_data, list):
            packages_data = []
    except (json.JSONDecodeError, ValueError):
        packages_data = []

    packages = [WithdrawPackageItem(**item) for item in packages_data if isinstance(item, dict)]
    return Success(data={"packages": [p.model_dump() for p in packages]})


@router.put("", summary="更新提现配置")
async def update_withdraw_config(config_in: WithdrawConfigIn):
    """更新提现配置"""
    try:
        packages_json = json.dumps(
            [p.model_dump() for p in config_in.packages],
            ensure_ascii=False,
        )

        config_obj = await SystemConfig.filter(cfg_key="withdraw_packages").first()
        if config_obj:
            config_obj.cfg_value = packages_json
            await config_obj.save(update_fields=["cfg_value"])
        else:
            await SystemConfig.create(
                cfg_key="withdraw_packages",
                cfg_value=packages_json,
                description="提现套餐配置",
            )

        try:
            redis = await get_redis()
            await redis.delete(SYSTEM_CONFIG_CACHE_KEY)
        except Exception as e:
            logger.warning(f"Failed to clear cache: {e}")

        return Success(msg="配置已更新")
    except Exception as e:
        logger.error(f"Failed to update withdraw config: {e}")
        raise HTTPException(status_code=500, detail="配置更新失败")
