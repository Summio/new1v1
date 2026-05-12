from tortoise import fields

from .base import BaseModel, TimestampMixin


class SystemNotificationTask(BaseModel, TimestampMixin):
    """后台系统通知任务/模板。"""

    title = fields.CharField(max_length=100, description="通知标题")
    summary = fields.CharField(max_length=200, description="通知摘要")
    content = fields.TextField(description="通知正文，纯文本")
    type = fields.CharField(max_length=20, description="announcement/account/review/interaction", db_index=True)
    status = fields.CharField(
        max_length=20, default="draft", description="draft/scheduled/running/paused/completed/cancelled", db_index=True
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
        table = "system_notification_task"


class SystemNotification(BaseModel):
    """一次实际发送出的系统通知实例。"""

    task_id = fields.BigIntField(null=True, description="后台通知任务ID", db_index=True)
    title = fields.CharField(max_length=100, description="通知标题")
    summary = fields.CharField(max_length=200, description="通知摘要")
    content = fields.TextField(description="通知正文，纯文本")
    type = fields.CharField(max_length=20, description="announcement/account/review/interaction", db_index=True)
    source = fields.CharField(max_length=20, default="admin", description="admin/system", db_index=True)
    publish_at = fields.DatetimeField(null=True, description="计划发布时间")
    published_at = fields.DatetimeField(null=True, description="实际发布时间", db_index=True)
    scheduled_run_at = fields.DatetimeField(null=True, description="调度批次时间")
    run_key = fields.CharField(max_length=120, null=True, unique=True, description="调度批次幂等键")
    biz_key = fields.CharField(max_length=160, null=True, unique=True, description="业务幂等键")
    created_at = fields.DatetimeField(auto_now_add=True, db_index=True)

    class Meta:
        table = "system_notification"
        unique_together = (("task_id", "scheduled_run_at"),)


class SystemNotificationReceipt(BaseModel):
    """用户通知回执。"""

    notification_id = fields.BigIntField(description="通知实例ID", db_index=True)
    user_id = fields.BigIntField(description="App用户ID", db_index=True)
    read_at = fields.DatetimeField(null=True, description="已读时间", db_index=True)
    created_at = fields.DatetimeField(auto_now_add=True, db_index=True)

    class Meta:
        table = "system_notification_receipt"
        unique_together = (("notification_id", "user_id"),)
