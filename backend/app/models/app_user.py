from tortoise import fields

from .base import BaseModel, TimestampMixin


class AppUser(BaseModel, TimestampMixin):
    """App 用户（普通用户 + 主播）"""
    phone = fields.CharField(max_length=20, unique=True, description="手机号(登录账号)", index=True)
    password = fields.CharField(max_length=128, description="密码(加密)")
    nickname = fields.CharField(max_length=30, null=True, description="昵称")
    avatar = fields.CharField(max_length=500, null=True, description="头像URL")
    gender = fields.CharField(max_length=10, null=True, default="secret", description="male/female/secret")
    birth_date = fields.DateField(null=True, description="出生日期")
    height_cm = fields.IntField(null=True, description="身高(cm)")
    weight_kg = fields.IntField(null=True, description="体重(kg)")
    location_city = fields.CharField(max_length=50, null=True, description="所在地(省-市)")
    album_photos = fields.JSONField(null=True, description="相册URL列表(最多6张)")
    cover_url = fields.CharField(max_length=500, null=True, description="封面URL(必须来自相册)")
    status = fields.CharField(max_length=20, null=True, default="normal", description="normal/banned", index=True)
    is_anchor = fields.BooleanField(default=False, description="是否为签约主播", index=True)
    anchor_intro = fields.CharField(max_length=500, null=True, description="主播简介")
    anchor_tags = fields.JSONField(null=True, description="主播标签列表")
    anchor_call_price = fields.BigIntField(default=100, description="主播通话价格(分/分钟)")
    anchor_apply_status = fields.CharField(
        max_length=20,
        default="none",
        description="主播申请状态 none/pending/approved/rejected",
        index=True,
    )
    anchor_apply_at = fields.DatetimeField(null=True, description="主播申请时间")
    anchor_reviewed_at = fields.DatetimeField(null=True, description="主播审核时间")
    anchor_reject_reason = fields.CharField(max_length=500, null=True, description="主播申请拒绝原因")
    coins = fields.BigIntField(default=0, description="金币余额(分)")
    diamonds = fields.BigIntField(default=0, description="钻石余额(分)")
    frozen_diamonds = fields.BigIntField(default=0, description="冻结钻石(分)")
    ban_reason = fields.CharField(max_length=500, null=True, description="封禁原因")
    last_login = fields.DatetimeField(null=True, description="最后登录时间")

    class Meta:
        table = "app_user"
