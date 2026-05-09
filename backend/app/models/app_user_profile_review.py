from tortoise import fields

from .base import BaseModel, TimestampMixin


class AppUserProfileReviewApply(BaseModel, TimestampMixin):
    user_id = fields.BigIntField(description="App用户ID", db_index=True)
    status = fields.CharField(
        max_length=20,
        default="pending",
        description="pending/reviewing/completed/cancelled",
        db_index=True,
    )
    before_snapshot = fields.JSONField(null=True, description="提交前资料快照")
    after_snapshot = fields.JSONField(null=True, description="提交后资料快照")
    review_items = fields.JSONField(null=True, description="审核项列表")
    submitted_at = fields.DatetimeField(null=True, description="提交时间")
    completed_at = fields.DatetimeField(null=True, description="完成时间")
    completed_by = fields.BigIntField(null=True, description="完成审核的后台用户ID")
    review_remark = fields.CharField(max_length=500, null=True, description="审核备注")

    class Meta:
        table = "app_user_profile_review_apply"
