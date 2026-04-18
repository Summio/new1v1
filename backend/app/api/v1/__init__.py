from .system_config import system_config_router
from .withdraw import router as withdraw_router
from fastapi import APIRouter

from app.core.dependency import DependPermission

from .app import app_router
from .apis import apis_router
from .auditlog import auditlog_router
from .base import base_router
from .depts import depts_router
from .menus import menus_router
from .roles import roles_router
from .users import users_router
from app.websocket.router import router as ws_router

v1_router = APIRouter()

v1_router.include_router(base_router, prefix="/base")
v1_router.include_router(app_router, prefix="/app")
v1_router.include_router(ws_router, prefix="")  # WebSocket: /api/v1/ws/app
v1_router.include_router(users_router, prefix="/user", dependencies=[DependPermission])
v1_router.include_router(roles_router, prefix="/role", dependencies=[DependPermission])
v1_router.include_router(menus_router, prefix="/menu", dependencies=[DependPermission])
v1_router.include_router(apis_router, prefix="/api", dependencies=[DependPermission])
v1_router.include_router(depts_router, prefix="/dept", dependencies=[DependPermission])
v1_router.include_router(auditlog_router, prefix="/auditlog", dependencies=[DependPermission])
v1_router.include_router(system_config_router, prefix="/system_config", dependencies=[DependPermission])
v1_router.include_router(withdraw_router, prefix="/withdraw", dependencies=[DependPermission])
