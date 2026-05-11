from tortoise import fields

from .base import BaseModel, TimestampMixin


class UserBlock(BaseModel, TimestampMixin):
    """用户黑名单关系"""

    blocker_id = fields.BigIntField(db_index=True, description="拉黑发起用户ID")
    blocked_id = fields.BigIntField(db_index=True, description="被拉黑用户ID")
    reason = fields.CharField(max_length=255, null=True, description="拉黑备注")

    class Meta:
        table = "user_block"
        unique_together = (("blocker_id", "blocked_id"),)
