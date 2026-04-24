import os
import warnings

from aerich import Command
from fastapi import FastAPI
from fastapi.middleware import Middleware
from fastapi.middleware.cors import CORSMiddleware
from tortoise.expressions import Q

from app.api import api_router
from app.controllers.api import api_controller
from app.controllers.user import UserCreate, user_controller
from app.core.exceptions import (
    DoesNotExist,
    DoesNotExistHandle,
    HTTPException,
    HttpExcHandle,
    IntegrityError,
    IntegrityHandle,
    RequestValidationError,
    RequestValidationHandle,
    ResponseValidationError,
    ResponseValidationHandle,
    UnhandledExceptionHandle,
)
from app.log import logger
from app.models.admin import Api, Menu, Role
from app.schemas.menus import MenuType
from app.settings.config import settings

from .middlewares import BackGroundTaskMiddleware, HttpAuditLogMiddleware
from .middlewares import AppFriendlyStatusMiddleware


def build_operation_children(parent_id: int) -> list[Menu]:
    return [
        Menu(
            menu_type=MenuType.MENU,
            name="用户管理",
            path="app-user",
            order=1,
            parent_id=parent_id,
            icon="material-symbols:group-outline-rounded",
            is_hidden=False,
            component="/operation/app-user",
            keepalive=False,
        ),
        Menu(
            menu_type=MenuType.MENU,
            name="通话记录",
            path="call-record",
            order=2,
            parent_id=parent_id,
            icon="material-symbols:call-log-outline-rounded",
            is_hidden=False,
            component="/operation/call-record",
            keepalive=False,
        ),
    ]


async def _ensure_menu_exists(
    *,
    name: str,
    parent_id: int,
    menu_type: MenuType,
    path: str,
    order: int,
    icon: str,
    component: str,
    keepalive: bool = False,
    redirect: str | None = None,
    is_hidden: bool = False,
) -> Menu:
    existing = await Menu.filter(path=path, parent_id=parent_id).first()
    if existing:
        return existing
    return await Menu.create(
        menu_type=menu_type,
        name=name,
        path=path,
        order=order,
        parent_id=parent_id,
        icon=icon,
        is_hidden=is_hidden,
        component=component,
        keepalive=keepalive,
        redirect=redirect,
    )


def make_middlewares():
    middleware = [
        Middleware(
            CORSMiddleware,
            allow_origins=settings.CORS_ORIGINS,
            allow_credentials=settings.CORS_ALLOW_CREDENTIALS,
            allow_methods=settings.CORS_ALLOW_METHODS,
            allow_headers=settings.CORS_ALLOW_HEADERS,
        ),
        Middleware(BackGroundTaskMiddleware),
        Middleware(AppFriendlyStatusMiddleware),
        Middleware(
            HttpAuditLogMiddleware,
            methods=["GET", "POST", "PUT", "DELETE"],
            exclude_paths=[
                "/api/v1/base/access_token",
                "/docs",
                "/openapi.json",
            ],
        ),
    ]
    return middleware


def register_exceptions(app: FastAPI):
    app.add_exception_handler(DoesNotExist, DoesNotExistHandle)
    app.add_exception_handler(HTTPException, HttpExcHandle)
    app.add_exception_handler(IntegrityError, IntegrityHandle)
    app.add_exception_handler(RequestValidationError, RequestValidationHandle)
    app.add_exception_handler(ResponseValidationError, ResponseValidationHandle)
    app.add_exception_handler(Exception, UnhandledExceptionHandle)


def register_routers(app: FastAPI, prefix: str = "/api"):
    app.include_router(api_router, prefix=prefix)


async def init_superuser():
    user = await user_controller.model.exists()
    if not user:
        _password = os.getenv("ADMIN_PASSWORD", "")
        if not _password:
            if os.getenv("DEBUG", "false").lower() != "true":
                warnings.warn(
                    "环境变量 ADMIN_PASSWORD 未设置，生产环境请通过 ADMIN_PASSWORD 配置管理员密码",
                    UserWarning,
                    stacklevel=2,
                )
                _password = ""  # 不创建默认管理员
            else:
                _password = "123456"
                warnings.warn(
                    "使用了默认管理员密码 123456（DEBUG 模式），生产环境请通过 ADMIN_PASSWORD 配置",
                    UserWarning,
                    stacklevel=2,
                )
        if not _password:
            return
        await user_controller.create_user(
            UserCreate(
                username="admin",
                email="admin@admin.com",
                password=_password,
                is_active=True,
                is_superuser=True,
            )
        )


async def init_menus():
    parent_menu = await _ensure_menu_exists(
        name="系统管理",
        parent_id=0,
        menu_type=MenuType.CATALOG,
        path="/system",
        order=1,
        icon="carbon:gui-management",
        is_hidden=False,
        component="Layout",
        keepalive=False,
        redirect="/system/user",
    )
    system_children = [
        {
            "name": "用户管理",
            "path": "user",
            "order": 1,
            "icon": "material-symbols:person-outline-rounded",
            "component": "/system/user",
        },
        {"name": "角色管理", "path": "role", "order": 2, "icon": "carbon:user-role", "component": "/system/role"},
        {
            "name": "菜单管理",
            "path": "menu",
            "order": 3,
            "icon": "material-symbols:list-alt-outline",
            "component": "/system/menu",
        },
        {"name": "API管理", "path": "api", "order": 4, "icon": "ant-design:api-outlined", "component": "/system/api"},
        {"name": "部门管理", "path": "dept", "order": 5, "icon": "mingcute:department-line", "component": "/system/dept"},
        {"name": "审计日志", "path": "auditlog", "order": 6, "icon": "ph:clipboard-text-bold", "component": "/system/auditlog"},
        {
            "name": "系统配置",
            "path": "config",
            "order": 7,
            "icon": "material-symbols:settings-outline-rounded",
            "component": "/system/config",
        },
    ]
    for child in system_children:
        await _ensure_menu_exists(
            name=child["name"],
            parent_id=parent_menu.id,
            menu_type=MenuType.MENU,
            path=child["path"],
            order=child["order"],
            icon=child["icon"],
            component=child["component"],
            keepalive=False,
        )

    operation_parent = await _ensure_menu_exists(
        name="运营中心",
        parent_id=0,
        menu_type=MenuType.CATALOG,
        path="/operation",
        order=2,
        icon="material-symbols:monitoring-outline-rounded",
        is_hidden=False,
        component="Layout",
        keepalive=False,
        redirect="/operation/app-user",
    )
    for child in build_operation_children(parent_id=operation_parent.id):
        await _ensure_menu_exists(
            name=child.name,
            parent_id=operation_parent.id,
            menu_type=child.menu_type,
            path=child.path,
            order=child.order,
            icon=child.icon,
            component=child.component,
            keepalive=child.keepalive,
            is_hidden=child.is_hidden,
        )

    await _ensure_menu_exists(
        name="一级菜单",
        parent_id=0,
        menu_type=MenuType.MENU,
        path="/top-menu",
        order=99,
        icon="material-symbols:featured-play-list-outline",
        is_hidden=False,
        component="/top-menu",
        keepalive=False,
        redirect="",
    )


async def init_apis():
    apis = await api_controller.model.exists()
    if not apis:
        await api_controller.refresh_api()


async def init_db():
    command = Command(tortoise_config=settings.TORTOISE_ORM)
    try:
        await command.init_db(safe=True)
    except FileExistsError:
        pass

    await command.init()
    try:
        await command.migrate()
    except (AttributeError, Exception) as e:
        import asyncclick.exceptions
        # aerich 在部分 M2M 差异场景下会抛出 TypeError: 'bool' object is not subscriptable
        # 该异常来自迁移对比逻辑，避免阻塞服务启动，后续可通过手动 aerich migrate 处理。
        if isinstance(e, TypeError) and "bool' object is not subscriptable" in str(e):
            logger.warning("skip auto migrate due to aerich m2m diff bug: {}", str(e))
            return
        if isinstance(e, (asyncclick.exceptions.UsageError, AttributeError)):
            logger.error(
                "unable to retrieve model history from database. "
                "startup auto-recovery is disabled to avoid deleting migrations. "
                "please run manual migration recovery."
            )
            raise RuntimeError("migration history retrieval failed, manual migration recovery required") from e
        else:
            raise

    await command.upgrade(run_in_transaction=True)


async def init_roles():
    roles = await Role.exists()
    if not roles:
        admin_role = await Role.create(
            name="管理员",
            desc="管理员角色",
        )
        user_role = await Role.create(
            name="普通用户",
            desc="普通用户角色",
        )

        # 分配所有API给管理员角色
        all_apis = await Api.all()
        await admin_role.apis.add(*all_apis)
        # 分配所有菜单给管理员和普通用户
        all_menus = await Menu.all()
        await admin_role.menus.add(*all_menus)
        await user_role.menus.add(*all_menus)

        # 为普通用户分配基本API
        basic_apis = await Api.filter(Q(method__in=["GET"]) | Q(tags="基础模块"))
        await user_role.apis.add(*basic_apis)
        return

    # 兼容存量环境：为所有历史角色补齐运营中心菜单与通话记录查询权限（幂等）
    all_roles = await Role.all()
    operation_menus = await Menu.filter(path__in=["/operation", "app-user", "call-record"]).all()
    if all_roles and operation_menus:
        for role in all_roles:
            await role.menus.add(*operation_menus)

    call_record_api = await Api.filter(method="GET", path="/api/v1/call_record/list").first()
    if call_record_api and all_roles:
        for role in all_roles:
            await role.apis.add(call_record_api)

    # 兼容存量环境：确保管理员角色始终拥有全部菜单与API（幂等）
    admin_role = await Role.filter(name="管理员").first()
    if admin_role:
        all_apis = await Api.all()
        if all_apis:
            await admin_role.apis.add(*all_apis)
        all_menus = await Menu.all()
        if all_menus:
            await admin_role.menus.add(*all_menus)


async def init_data():
    await init_db()
    await init_superuser()
    await init_menus()
    await init_apis()
    await init_roles()
