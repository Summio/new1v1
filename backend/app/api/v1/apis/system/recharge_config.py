import json
from fastapi import APIRouter

from app.core.redis import get_redis
from app.models.system_config import SystemConfig, SYSTEM_CONFIG_CACHE_KEY
from app.schemas.base import Success
from app.schemas.system import RechargeConfigIn, RechargeConfigOut, RechargePackageItem

router = APIRouter()


@router.get("", summary="获取充值配置", response_model=Success)
async def get_recharge_config():
    """获取当前充值配置"""
    config_value = await SystemConfig.get_value("recharge_packages", "[]")
    try:
        packages_data = json.loads(config_value)
        if not isinstance(packages_data, list):
            packages_data = []
    except (json.JSONDecodeError, ValueError):
        packages_data = []

    packages = [RechargePackageItem(**item) for item in packages_data if isinstance(item, dict)]
    return Success(data={"packages": [p.model_dump() for p in packages]})


@router.put("", summary="更新充值配置", response_model=Success)
async def update_recharge_config(config_in: RechargeConfigIn):
    """更新充值配置"""
    # 序列化为 JSON
    packages_json = json.dumps(
        [p.model_dump() for p in config_in.packages],
        ensure_ascii=False
    )

    # 更新或创建配置
    config_obj = await SystemConfig.filter(cfg_key="recharge_packages").first()
    if config_obj:
        config_obj.cfg_value = packages_json
        await config_obj.save(update_fields=["cfg_value"])
    else:
        await SystemConfig.create(
            cfg_key="recharge_packages",
            cfg_value=packages_json,
            description="充值套餐配置"
        )

    # 清除 Redis 缓存
    try:
        redis = await get_redis()
        await redis.delete(SYSTEM_CONFIG_CACHE_KEY)
    except Exception as e:
        # 缓存清除失败不影响主流程
        import logging
        logging.warning(f"Failed to clear cache: {e}")

    return Success(msg="配置已更新")
