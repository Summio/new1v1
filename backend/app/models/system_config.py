from app.core.redis import get_redis
from tortoise import fields

from .base import BaseModel, TimestampMixin

SYSTEM_CONFIG_CACHE_KEY = "system_config:all"
SYSTEM_CONFIG_CACHE_TTL = 60  # 秒


class SystemConfig(BaseModel, TimestampMixin):
    """系统配置（键值对）"""
    cfg_key = fields.CharField(max_length=64, unique=True, description="配置键")
    cfg_value = fields.TextField(description="配置值")
    description = fields.CharField(max_length=255, null=True, description="说明")

    class Meta:
        table = "system_config"

    @classmethod
    async def get_value(cls, key: str, default: str = "") -> str:
        """获取配置值，不存在则返回默认值"""
        obj = await cls.filter(cfg_key=key).first()
        return obj.cfg_value if obj else default

    @classmethod
    async def get_all_as_dict(cls) -> dict:
        """P-5 修复：获取所有配置为字典（Redis 缓存，60s TTL）"""
        import json

        try:
            redis = await get_redis()
            cached = await redis.get(SYSTEM_CONFIG_CACHE_KEY)
            if cached:
                return json.loads(cached)
        except Exception:  # noqa: BLE001
            pass
        configs = await cls.all()
        result = {c.cfg_key: c.cfg_value for c in configs}
        try:
            redis = await get_redis()
            await redis.setex(SYSTEM_CONFIG_CACHE_KEY, SYSTEM_CONFIG_CACHE_TTL, json.dumps(result))
        except Exception:  # noqa: BLE001
            pass
        return result
