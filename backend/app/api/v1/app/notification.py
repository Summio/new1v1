from fastapi import APIRouter, Query

from app.core.ctx import CTX_APP_USER_ID
from app.schemas.base import Fail, Success, SuccessExtra
from app.services.system_notification_service import (
    get_user_notification_detail,
    get_user_unread_summary,
    list_user_notifications,
    mark_all_notifications_read,
    mark_notification_read,
    mark_notification_unread,
)

router = APIRouter()


def _current_user_id() -> int | None:
    user_id = CTX_APP_USER_ID.get()
    return int(user_id) if user_id else None


@router.get("/notifications", summary="系统通知列表")
async def list_notifications(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
):
    user_id = _current_user_id()
    if not user_id:
        return Fail(code=401, msg="用户不存在")
    rows, total = await list_user_notifications(user_id=user_id, page=page, page_size=page_size)
    return SuccessExtra(data=rows, total=total, page=page, page_size=page_size)


@router.get("/notifications/unread-count", summary="系统通知未读数")
async def get_unread_count():
    user_id = _current_user_id()
    if not user_id:
        return Fail(code=401, msg="用户不存在")
    return Success(data=await get_user_unread_summary(user_id=user_id))


@router.get("/notifications/{notification_id}", summary="系统通知详情")
async def get_notification_detail(notification_id: int):
    user_id = _current_user_id()
    if not user_id:
        return Fail(code=401, msg="用户不存在")
    detail = await get_user_notification_detail(user_id=user_id, notification_id=notification_id)
    if not detail:
        return Fail(code=404, msg="通知不存在")
    return Success(data=detail)


@router.post("/notifications/{notification_id}/read", summary="标记系统通知已读")
async def read_notification(notification_id: int):
    user_id = _current_user_id()
    if not user_id:
        return Fail(code=401, msg="用户不存在")
    ok = await mark_notification_read(user_id=user_id, notification_id=notification_id)
    if not ok:
        return Fail(code=404, msg="通知不存在")
    return Success(msg="操作成功")


@router.post("/notifications/{notification_id}/unread", summary="标记系统通知未读")
async def unread_notification(notification_id: int):
    user_id = _current_user_id()
    if not user_id:
        return Fail(code=401, msg="用户不存在")
    ok = await mark_notification_unread(user_id=user_id, notification_id=notification_id)
    if not ok:
        return Fail(code=404, msg="通知不存在")
    return Success(msg="操作成功")


@router.post("/notifications/read-all", summary="全部系统通知已读")
async def read_all_notifications():
    user_id = _current_user_id()
    if not user_id:
        return Fail(code=401, msg="用户不存在")
    await mark_all_notifications_read(user_id=user_id)
    return Success(msg="操作成功")
