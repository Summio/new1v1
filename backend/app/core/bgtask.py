import asyncio
from datetime import datetime, timedelta, timezone

from loguru import logger
from starlette.background import BackgroundTasks

from .ctx import CTX_BG_TASKS

# AuditLog 保留天数（超过此天数的记录将被清理）
AUDIT_LOG_RETENTION_DAYS = 180


async def cleanup_old_audit_logs(retention_days: int = AUDIT_LOG_RETENTION_DAYS) -> int:
    """清理过期的审计日志记录。

    被 run_auditlog_cleanup 定期调用，返回删除的记录数量。
    """
    from app.models.admin import AuditLog

    cutoff = datetime.now(timezone(timedelta(hours=8))) - timedelta(days=retention_days)
    try:
        deleted = await AuditLog.filter(created_at__lt=cutoff).delete()
        logger.info("audit log cleanup: deleted {} records older than {} days", deleted, retention_days)
        return deleted
    except Exception as e:  # noqa: BLE001
        logger.exception("audit log cleanup failed: {}", str(e))
        return 0


async def run_auditlog_cleanup(stop_event: asyncio.Event) -> None:
    """定期清理过期审计日志的后台任务。"""
    from app.core.bgtask import cleanup_old_audit_logs

    interval_hours = 24
    while not stop_event.is_set():
        try:
            deleted = await cleanup_old_audit_logs()
            logger.info("auditlog periodic cleanup completed, deleted={}", deleted)
        except Exception as e:  # noqa: BLE001
            logger.exception("auditlog periodic cleanup error: {}", str(e))
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=interval_hours * 3600)
        except asyncio.TimeoutError:
            pass


class BgTasks:
    """后台任务统一管理"""

    @classmethod
    async def init_bg_tasks_obj(cls):
        """实例化后台任务，并设置到上下文"""
        bg_tasks = BackgroundTasks()
        CTX_BG_TASKS.set(bg_tasks)

    @classmethod
    async def get_bg_tasks_obj(cls):
        """从上下文中获取后台任务实例"""
        return CTX_BG_TASKS.get()

    @classmethod
    async def add_task(cls, func, *args, **kwargs):
        """添加后台任务"""
        bg_tasks = await cls.get_bg_tasks_obj()
        bg_tasks.add_task(func, *args, **kwargs)

    @classmethod
    async def execute_tasks(cls):
        """执行后台任务，一般是请求结果返回之后执行"""
        bg_tasks = await cls.get_bg_tasks_obj()
        if bg_tasks.tasks:
            await bg_tasks()
