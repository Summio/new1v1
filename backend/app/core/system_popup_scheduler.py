from app.log import logger

DEFAULT_POLL_SECONDS = 30


async def run_system_popup_scheduler(
    stop_event,
    *,
    poll_seconds: int = DEFAULT_POLL_SECONDS,
) -> None:
    """兼容旧导入路径；系统弹窗已改为 App 拉取时结算。"""
    logger.info("system popup scheduler is disabled; popups materialize on pull")
