from tortoise import fields

from .base import BaseModel, TimestampMixin


class AppUser(BaseModel, TimestampMixin):
    """App 用户（普通用户 + 认证用户）"""

    phone = fields.CharField(max_length=20, unique=True, description="手机号(登录账号)", db_index=True)
    password = fields.CharField(max_length=128, description="密码(加密)")
    nickname = fields.CharField(max_length=30, null=True, description="昵称")
    avatar = fields.CharField(max_length=500, null=True, description="头像URL")
    signature = fields.CharField(max_length=500, null=True, description="个性签名")
    gender = fields.CharField(max_length=10, null=True, default="male", description="male/female")
    birth_date = fields.DateField(null=True, description="出生日期")
    height_cm = fields.IntField(null=True, description="身高(cm)")
    weight_kg = fields.IntField(null=True, description="体重(kg)")
    location_city = fields.CharField(max_length=50, null=True, description="所在地(省-市)")
    album_photos = fields.JSONField(null=True, description="相册URL列表(最多6张)")
    cover_url = fields.CharField(max_length=500, null=True, description="封面URL(必须来自相册)")
    status = fields.CharField(max_length=20, null=True, default="normal", description="normal/banned", db_index=True)
    is_certified_user = fields.BooleanField(default=False, description="是否为真人认证用户", db_index=True)
    is_recommended = fields.BooleanField(default=False, description="是否首页推荐认证用户", db_index=True)
    recommend_weight = fields.IntField(default=0, description="认证用户推荐值", db_index=True)
    certified_intro = fields.CharField(max_length=500, null=True, description="认证用户简介")
    certified_tags = fields.JSONField(null=True, description="认证用户标签列表")
    certified_call_price = fields.BigIntField(default=0, description="认证用户通话价格(金币/分钟)")
    certification_status = fields.CharField(
        max_length=20,
        default="none",
        description="真人认证状态 none/pending/approved/rejected",
        db_index=True,
    )
    certification_apply_at = fields.DatetimeField(null=True, description="真人认证申请时间")
    certification_reviewed_at = fields.DatetimeField(null=True, description="真人认证审核时间")
    certification_reject_reason = fields.CharField(max_length=500, null=True, description="真人认证拒绝原因")
    certification_face_image = fields.CharField(max_length=500, null=True, description="真人认证正面照URL")
    coins = fields.DecimalField(max_digits=18, decimal_places=2, default=0, description="金币余额")
    diamonds = fields.DecimalField(max_digits=18, decimal_places=2, default=0, description="钻石余额")
    frozen_diamonds = fields.DecimalField(max_digits=18, decimal_places=2, default=0, description="冻结钻石")
    text_dnd_enabled = fields.BooleanField(default=False, description="文字勿扰开关")
    video_dnd_enabled = fields.BooleanField(default=False, description="视频勿扰开关")
    ranking_invisible_enabled = fields.BooleanField(default=False, description="榜单隐身开关")
    vip_expires_at = fields.DatetimeField(null=True, description="VIP到期时间", db_index=True)
    initial_profile_completed = fields.BooleanField(
        default=False,
        description="是否已完成初始资料",
        db_index=True,
    )
    ban_reason = fields.CharField(max_length=500, null=True, description="封禁原因")
    last_login = fields.DatetimeField(null=True, description="最后登录时间")

    class Meta:
        table = "app_user"
