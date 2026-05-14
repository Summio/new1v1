import asyncio

from app.log import logger
from app.services.system_popup_service import publish_due_popups

DEFAULT_POLL_SECONDS = 30


async def run_system_popup_scheduler(
    stop_event: asyncio.Event,
    *,
    poll_seconds: int = DEFAULT_POLL_SECONDS,
) -> None:
    """扫描并发布到期在线弹窗任务。"""
    while not stop_event.is_set():
        try:
            await publish_due_popups()
        except Exception as exc:
            logger.warning("system popup scheduler failed: {}", exc)
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=poll_seconds)
        except asyncio.TimeoutError:
            continue
