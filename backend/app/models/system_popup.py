from tortoise import fields

from .base import BaseModel, TimestampMixin


class SystemPopupTask(BaseModel, TimestampMixin):
    """后台在线弹窗任务。"""

    title = fields.CharField(max_length=50, description="弹窗标题")
    content = fields.TextField(description="弹窗正文，纯文本")
    type = fields.CharField(max_length=20, description="announcement/account/review/interaction", db_index=True)
    status = fields.CharField(
        max_length=20,
        default="draft",
        description="draft/scheduled/running/paused/completed/cancelled",
        db_index=True,
    )
    send_mode = fields.CharField(max_length=20, default="immediate", description="immediate/once/repeat", db_index=True)
    target_mode = fields.CharField(max_length=20, default="all", description="all/user_ids/filter", db_index=True)
    target_user_ids = fields.JSONField(null=True, description="指定用户ID列表")
    target_filters = fields.JSONField(null=True, description="筛选条件")
    publish_at = fields.DatetimeField(null=True, description="一次性发布时间")
    repeat_type = fields.CharField(max_length=20, null=True, description="daily/weekly/monthly")
    repeat_time = fields.CharField(max_length=5, null=True, description="HH:mm")
    repeat_weekday = fields.IntField(null=True, description="周几 0-6")
    repeat_month_day = fields.IntField(null=True, description="每月几号 1-31")
    start_at = fields.DatetimeField(null=True, description="周期开始时间")
    end_at = fields.DatetimeField(null=True, description="周期结束时间")
    max_runs = fields.IntField(null=True, description="最大发送次数")
    run_count = fields.IntField(default=0, description="已发送次数")
    next_run_at = fields.DatetimeField(null=True, description="下次发送时间", db_index=True)
    last_run_at = fields.DatetimeField(null=True, description="上次发送时间")
    created_by = fields.BigIntField(null=True, description="创建后台用户ID")

    class Meta:
        table = "system_popup_task"


class SystemPopup(BaseModel):
    """一次实际发布出的在线弹窗实例。"""

    task_id = fields.BigIntField(null=True, description="后台弹窗任务ID", db_index=True)
    title = fields.CharField(max_length=50, description="弹窗标题")
    content = fields.TextField(description="弹窗正文，纯文本")
    type = fields.CharField(max_length=20, description="announcement/account/review/interaction", db_index=True)
    publish_at = fields.DatetimeField(null=True, description="计划发布时间")
    published_at = fields.DatetimeField(null=True, description="实际发布时间", db_index=True)
    scheduled_run_at = fields.DatetimeField(null=True, description="调度批次时间")
    run_key = fields.CharField(max_length=120, null=True, unique=True, description="调度批次幂等键")
    created_at = fields.DatetimeField(auto_now_add=True, db_index=True)

    class Meta:
        table = "system_popup"
        unique_together = (("task_id", "scheduled_run_at"),)


class SystemPopupReceipt(BaseModel):
    """用户在线弹窗推送和确认回执。"""

    popup_id = fields.BigIntField(description="弹窗实例ID", db_index=True)
    user_id = fields.BigIntField(description="App用户ID", db_index=True)
    pushed_at = fields.DatetimeField(null=True, description="推送时间", db_index=True)
    ack_at = fields.DatetimeField(null=True, description="确认时间", db_index=True)
    created_at = fields.DatetimeField(auto_now_add=True, db_index=True)

    class Meta:
        table = "system_popup_receipt"
        unique_together = (("popup_id", "user_id"),)
