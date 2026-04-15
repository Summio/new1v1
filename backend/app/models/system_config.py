from tortoise import fields

from .base import BaseModel, TimestampMixin


class SystemConfig(BaseModel, TimestampMixin):
    """系统配置（键值对）"""
    cfg_key = fields.CharField(max_length=64, unique=True, description="配置键")
    cfg_value = fields.CharField(max_length=255, description="配置值")
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
        """获取所有配置为字典"""
        configs = await cls.all()
        return {c.cfg_key: c.cfg_value for c in configs}
