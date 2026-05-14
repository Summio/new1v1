from tortoise import fields

from .base import BaseModel, TimestampMixin


class AppUserCommonPhrase(BaseModel, TimestampMixin):
    """真人认证用户常用语槽位"""

    user_id = fields.BigIntField(description="App用户ID", db_index=True)
    slot_index = fields.IntField(description="槽位编号 1/2/3", db_index=True)
    approved_content = fields.CharField(max_length=50, default="", description="已审核通过内容")
    pending_content = fields.CharField(max_length=50, default="", description="待审核/被驳回内容")
    review_status = fields.CharField(
        max_length=20,
        default="none",
        description="none/pending/approved/rejected",
        db_index=True,
    )
    review_remark = fields.CharField(max_length=500, default="", description="审核备注/驳回原因")
    submitted_at = fields.DatetimeField(null=True, description="提交时间")
    reviewed_at = fields.DatetimeField(null=True, description="审核时间")
    reviewed_by = fields.BigIntField(null=True, description="审核后台用户ID")

    class Meta:
        table = "app_user_common_phrase"
        unique_together = (("user_id", "slot_index"),)
