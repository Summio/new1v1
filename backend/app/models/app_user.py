from tortoise import fields

from .base import BaseModel, TimestampMixin


class AppUser(BaseModel, TimestampMixin):
    """App 用户（普通用户 + 主播）"""
    phone = fields.CharField(max_length=20, unique=True, description="手机号(登录账号)", index=True)
    password = fields.CharField(max_length=128, description="密码(加密)")
    nickname = fields.CharField(max_length=30, null=True, description="昵称")
    avatar = fields.CharField(max_length=500, null=True, description="头像URL")
    gender = fields.CharField(max_length=10, null=True, default="secret", description="male/female/secret")
    balance = fields.IntField(default=0, description="钱包余额(分)")
    status = fields.CharField(max_length=20, null=True, default="normal", description="normal/banned", index=True)
    is_anchor = fields.BooleanField(default=False, description="是否为签约主播", index=True)
    frozen_balance = fields.IntField(default=0, description="冻结余额(分)", index=True)
    coins = fields.IntField(default=0, description="金币余额(分)")
    diamonds = fields.IntField(default=0, description="钻石余额(分)")
    frozen_diamonds = fields.IntField(default=0, description="冻结钻石(分)")
    ban_reason = fields.CharField(max_length=500, null=True, description="封禁原因")
    last_login = fields.DatetimeField(null=True, description="最后登录时间")

    class Meta:
        table = "app_user"
