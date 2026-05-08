from tortoise import fields

from .base import BaseModel, TimestampMixin


class Moment(BaseModel, TimestampMixin):
    """用户动态"""

    user_id = fields.BigIntField(description="用户ID", db_index=True)
    content = fields.CharField(max_length=500, null=True, description="文本内容，500字以内")
    is_pinned = fields.BooleanField(default=False, description="是否置顶", db_index=True)
    pinned_at = fields.DatetimeField(null=True, description="置顶时间", db_index=True)
    recommend_override = fields.BooleanField(null=True, description="单条推荐覆盖值", db_index=True)

    class Meta:
        table = "moments"


class MomentMedia(BaseModel):
    """动态媒体（图片/视频）"""

    moment = fields.ForeignKeyField(
        model_name="models.Moment",
        related_name="media_list",
        null=True,
        on_delete=fields.CASCADE,
        description="所属动态ID",
    )
    url = fields.CharField(max_length=500, description="媒体URL")
    media_type = fields.IntField(description="1=图片, 2=视频")  # 1=图片, 2=视频
    sort_order = fields.IntField(default=0, description="排序序号")
    cover_url = fields.CharField(max_length=500, null=True, description="视频封面URL")
    duration = fields.IntField(null=True, description="视频时长（秒）")

    class Meta:
        table = "moment_media"
