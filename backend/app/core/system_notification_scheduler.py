import asyncio

from app.log import logger
from app.services.system_notification_service import publish_due_notifications

DEFAULT_POLL_SECONDS = 30


async def run_system_notification_scheduler(
    stop_event: asyncio.Event,
    *,
    poll_seconds: int = DEFAULT_POLL_SECONDS,
) -> None:
    """扫描并发布到期系统通知任务。"""
    while not stop_event.is_set():
        try:
            await publish_due_notifications()
        except Exception as exc:
            logger.warning("system notification scheduler failed: {}", exc)
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=poll_seconds)
        except asyncio.TimeoutError:
            continue
