from tortoise import fields

from .base import BaseModel, TimestampMixin


class Feedback(BaseModel, TimestampMixin):
    """意见反馈"""

    user_id = fields.BigIntField(description="用户ID", db_index=True)
    content = fields.CharField(max_length=1000, description="意见反馈内容")

    class Meta:
        table = "feedback"
