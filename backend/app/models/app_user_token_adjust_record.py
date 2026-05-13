from tortoise import fields

from .base import BaseModel, TimestampMixin


class AppUserTokenAdjustRecord(BaseModel, TimestampMixin):
    """后台代币调整审计记录。"""

    app_user_id = fields.BigIntField(description="被调整的App用户ID", db_index=True)
    operator_user_id = fields.BigIntField(description="后台操作人用户ID", db_index=True)
    operator_username = fields.CharField(max_length=64, default="", description="后台操作人用户名快照")
    asset_type = fields.CharField(max_length=20, description="资产类型 coins/diamonds", db_index=True)
    action = fields.CharField(max_length=20, description="调整方向 increase/decrease", db_index=True)
    amount = fields.DecimalField(max_digits=18, decimal_places=2, description="调整数量")
    before_amount = fields.DecimalField(max_digits=18, decimal_places=2, description="调整前余额")
    after_amount = fields.DecimalField(max_digits=18, decimal_places=2, description="调整后余额")
    reason = fields.CharField(max_length=500, description="操作原因")

    class Meta:
        table = "app_user_token_adjust_record"
