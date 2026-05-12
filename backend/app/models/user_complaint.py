from tortoise import fields

from .base import BaseModel, TimestampMixin


class UserComplaint(BaseModel, TimestampMixin):
    """用户投诉记录"""

    complainant_id = fields.BigIntField(db_index=True, description="投诉人用户ID")
    target_user_id = fields.BigIntField(db_index=True, description="被投诉用户ID")
    reason = fields.CharField(max_length=64, description="投诉原因")
    content = fields.CharField(max_length=1000, description="投诉补充说明")
    status = fields.CharField(max_length=32, default="pending", db_index=True, description="处理状态")
    handle_remark = fields.CharField(max_length=1000, null=True, description="最后处理备注")
    handled_by = fields.BigIntField(null=True, description="最后处理管理员ID")
    handled_at = fields.DatetimeField(null=True, description="最后处理时间")

    class Meta:
        table = "user_complaint"
