from fastapi import APIRouter

from app.core.ctx import CTX_APP_USER_ID
from app.schemas.base import Fail, Success
from app.schemas.system_popup import SystemPopupStartupIn
from app.services.system_popup_service import (
    PopupValidationError,
    ack_user_popup,
    fetch_pending_popups_for_user,
    fetch_startup_popups_for_user,
)

router = APIRouter()


def _current_user_id() -> int | None:
    user_id = CTX_APP_USER_ID.get()
    return int(user_id) if user_id else None


@router.post("/popups/startup", summary="获取App启动弹窗")
async def startup_popups(req_in: SystemPopupStartupIn):
    user_id = _current_user_id()
    if not user_id:
        return Fail(code=401, msg="用户不存在")
    try:
        items = await fetch_startup_popups_for_user(user_id=user_id, launch_id=req_in.launch_id)
    except PopupValidationError as exc:
        return Fail(code=400, msg=str(exc))
    return Success(data={"items": items})


@router.get("/popups/pending", summary="获取待展示弹窗")
async def pending_popups():
    user_id = _current_user_id()
    if not user_id:
        return Fail(code=401, msg="用户不存在")
    items = await fetch_pending_popups_for_user(user_id=user_id)
    return Success(data={"items": items})


@router.post("/popups/{popup_id}/ack", summary="确认在线弹窗")
async def ack_popup(popup_id: int):
    user_id = _current_user_id()
    if not user_id:
        return Fail(code=401, msg="用户不存在")
    ok = await ack_user_popup(user_id=user_id, popup_id=popup_id)
    if not ok:
        return Fail(code=404, msg="弹窗不存在")
    return Success(msg="操作成功")
