from contextlib import asynccontextmanager
import asyncio

from fastapi import FastAPI
from tortoise import Tortoise

from app.core.call_watchdog import run_call_watchdog
from app.core.exceptions import SettingNotFound
from app.core.init_app import (
    init_data,
    make_middlewares,
    register_exceptions,
    register_routers,
)
from app.core.redis import close_redis, get_redis

try:
    from app.settings.config import settings
except ImportError:
    raise SettingNotFound("Can not import settings")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 初始化 Redis
    await get_redis()
    # 初始化数据库
    await init_data()
    stop_event = asyncio.Event()
    watchdog_task = asyncio.create_task(run_call_watchdog(stop_event))
    try:
        yield
    finally:
        stop_event.set()
        await watchdog_task
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
    return app


app = create_app()
