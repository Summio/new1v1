from app.log import logger

DEFAULT_POLL_SECONDS = 30


async def run_system_notification_scheduler(
    stop_event,
    *,
    poll_seconds: int = DEFAULT_POLL_SECONDS,
) -> None:
    """兼容旧导入路径；系统通知已改为 App 拉取时结算。"""
    logger.info("system notification scheduler is disabled; notifications materialize on pull")
