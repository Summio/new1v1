from fastapi import APIRouter

from app.core.ctx import CTX_APP_USER_ID
from app.models import AppUser, UserComplaint
from app.schemas.base import Fail, Success
from app.schemas.user_complaint import ComplaintCreateIn

router = APIRouter()


@router.post("/complaint/create", summary="提交用户投诉")
async def create_complaint(req_in: ComplaintCreateIn):
    complainant_id = int(CTX_APP_USER_ID.get() or 0)
    if complainant_id <= 0:
        return Fail(code=401, msg="用户不存在")
    if complainant_id == int(req_in.target_user_id):
        return Fail(code=400, msg="不能投诉自己")

    target_user = await AppUser.filter(id=req_in.target_user_id).first()
    if not target_user:
        return Fail(code=404, msg="被投诉用户不存在")

    complaint = await UserComplaint.create(
        complainant_id=complainant_id,
        target_user_id=int(target_user.id),
        scene=req_in.scene,
        reason=req_in.reason.strip(),
        content=req_in.content.strip(),
        status="pending",
    )
    return Success(data={"complaint_id": int(complaint.id), "status": "pending"}, msg="投诉已提交")
