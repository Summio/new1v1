from tortoise import fields

from .base import BaseModel, TimestampMixin


class UserFollow(BaseModel, TimestampMixin):
    """用户关注关系"""

    follower_id = fields.BigIntField(index=True, description="关注者用户ID")
    following_id = fields.BigIntField(index=True, description="被关注用户ID")

    class Meta:
        table = "user_follow"
        unique_together = (("follower_id", "following_id"),)
