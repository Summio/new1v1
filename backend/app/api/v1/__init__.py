from fastapi import APIRouter

from app.core.dependency import DependPermission
from app.websocket.router import router as ws_router

from .apis import apis_router
from .apis.system import system_router
from .app import app_router
from .app_users import app_users_router
from .auditlog import auditlog_router
from .base import base_router
from .business_ledger import business_ledger_router
from .call_records import call_records_router
from .complaint import complaint_router
from .depts import depts_router
from .fee_bill import fee_bill_router
from .feedback import feedback_router
from .gift import gift_router
from .menus import menus_router
from .moments import moments_router
from .notification import notification_router
from .ranking import router as ranking_router
from .recharge import router as recharge_router
from .roles import roles_router
from .system_config import system_config_router, system_config_spec_router
from .token_adjust_record import token_adjust_record_router
from .users import users_router
from .withdraw import router as withdraw_router

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
v1_router.include_router(system_config_spec_router, prefix="/apis", dependencies=[DependPermission])
v1_router.include_router(token_adjust_record_router, prefix="/token_adjust_record", dependencies=[DependPermission])
v1_router.include_router(business_ledger_router, prefix="/business_ledger", dependencies=[DependPermission])
v1_router.include_router(withdraw_router, prefix="/withdraw", dependencies=[DependPermission])
v1_router.include_router(app_users_router, prefix="/app_user", dependencies=[DependPermission])
v1_router.include_router(feedback_router, prefix="/feedback", dependencies=[DependPermission])
v1_router.include_router(fee_bill_router, prefix="/fee_bill", dependencies=[DependPermission])
v1_router.include_router(call_records_router, prefix="/call_record", dependencies=[DependPermission])
v1_router.include_router(complaint_router, prefix="/complaint", dependencies=[DependPermission])
v1_router.include_router(gift_router, prefix="/gift", dependencies=[DependPermission])
v1_router.include_router(recharge_router, prefix="/recharge", dependencies=[DependPermission])
v1_router.include_router(ranking_router, prefix="/ranking", dependencies=[DependPermission])
v1_router.include_router(moments_router, prefix="/moment", dependencies=[DependPermission])
v1_router.include_router(notification_router, prefix="/notification", dependencies=[DependPermission])
v1_router.include_router(system_router, prefix="/apis/system", dependencies=[DependPermission])
