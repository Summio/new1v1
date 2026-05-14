import asyncio
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from tortoise import Tortoise

from app.core.bgtask import run_auditlog_cleanup
from app.core.call_watchdog import run_call_watchdog
from app.core.exceptions import SettingNotFound
from app.core.init_app import (
    init_db,
    make_middlewares,
    register_exceptions,
    register_routers,
)
from app.core.redis import close_redis, get_redis
from app.core.system_notification_scheduler import run_system_notification_scheduler
from app.core.system_popup_scheduler import run_system_popup_scheduler
from app.websocket.manager import get_manager

try:
    from app.settings.config import settings
except ImportError:
    raise SettingNotFound("Can not import settings")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 初始化 Redis
    await get_redis()
    # 仅初始化数据库连接；迁移与种子数据必须由显式任务执行，禁止随服务启动写库。
    await init_db(run_migrations=False)
    stop_event = asyncio.Event()
    watchdog_task = asyncio.create_task(run_call_watchdog(stop_event))
    auditlog_task = asyncio.create_task(run_auditlog_cleanup(stop_event))
    notification_task = asyncio.create_task(run_system_notification_scheduler(stop_event))
    popup_task = asyncio.create_task(run_system_popup_scheduler(stop_event))
    try:
        yield
    finally:
        stop_event.set()
        await watchdog_task
        await auditlog_task
        await notification_task
        await popup_task
        # 关闭 WebSocket Pub/Sub 监听
        try:
            await get_manager().stop_pubsub()
        except Exception:
            pass
        # 关闭 Redis
        await close_redis()
        # 关闭数据库
        await Tortoise.close_connections()


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.APP_TITLE,
        description=settings.APP_DESCRIPTION,
        version=settings.VERSION,
        openapi_url="/openapi.json",
        middleware=make_middlewares(),
        lifespan=lifespan,
    )
    register_exceptions(app)
    register_routers(app, prefix="/api")
    uploads_dir = Path(settings.BASE_DIR) / "uploads"
    uploads_dir.mkdir(parents=True, exist_ok=True)
    app.mount("/uploads", StaticFiles(directory=str(uploads_dir)), name="uploads")
    return app


app = create_app()
