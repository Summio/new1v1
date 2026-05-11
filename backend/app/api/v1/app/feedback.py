from fastapi import APIRouter

from app.core.ctx import CTX_APP_USER_OBJ
from app.models import Feedback
from app.schemas.base import Fail, Success
from app.schemas.feedback import FeedbackCreateIn

router = APIRouter()


@router.post("/feedback/create", summary="提交意见反馈")
async def create_feedback(req_in: FeedbackCreateIn):
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    content = req_in.content.strip()
    if not content:
        return Fail(code=400, msg="请填写意见反馈")

    await Feedback.create(user_id=app_user.id, content=content)
    return Success(msg="提交成功")
