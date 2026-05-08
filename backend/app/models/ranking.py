from tortoise import fields

from .base import BaseModel, TimestampMixin


class RankingSnapshot(BaseModel, TimestampMixin):
    """排行榜快照"""

    board = fields.CharField(max_length=20, description="榜单 charm/wealth/invite", db_index=True)
    period = fields.CharField(max_length=20, description="周期 day/week/month", db_index=True)
    period_start = fields.DatetimeField(description="统计开始时间", db_index=True)
    period_end = fields.DatetimeField(description="统计结束时间")
    user_id = fields.BigIntField(description="App 用户ID", db_index=True)
    rank = fields.IntField(description="排名", db_index=True)
    score = fields.DecimalField(max_digits=18, decimal_places=2, default=0, description="真实榜单分数")
    computed_at = fields.DatetimeField(description="快照计算时间", db_index=True)
    source_summary = fields.JSONField(null=True, description="来源摘要")

    class Meta:
        table = "ranking_snapshot"
        unique_together = (("board", "period", "period_start", "user_id"),)
        indexes = (("board", "period", "period_start", "rank"),)
