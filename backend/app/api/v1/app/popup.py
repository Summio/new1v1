from fastapi import APIRouter

from app.core.ctx import CTX_APP_USER_ID
from app.schemas.base import Fail, Success
from app.services.system_popup_service import ack_user_popup

router = APIRouter()


def _current_user_id() -> int | None:
    user_id = CTX_APP_USER_ID.get()
    return int(user_id) if user_id else None


@router.post("/popups/{popup_id}/ack", summary="确认在线弹窗")
async def ack_popup(popup_id: int):
    user_id = _current_user_id()
    if not user_id:
        return Fail(code=401, msg="用户不存在")
    ok = await ack_user_popup(user_id=user_id, popup_id=popup_id)
    if not ok:
        return Fail(code=404, msg="弹窗不存在")
    return Success(msg="操作成功")
