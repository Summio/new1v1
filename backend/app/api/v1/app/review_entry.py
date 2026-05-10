from fastapi import APIRouter

from app.core.ctx import CTX_APP_USER_OBJ
from app.schemas.base import Fail, Success
from app.services.review_entry_guard_service import build_review_entry_status

router = APIRouter()


@router.get("/review/entry-status", summary="查询资料编辑与动态发布入口状态")
async def get_review_entry_status():
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    return Success(data=await build_review_entry_status(int(app_user.id)))
