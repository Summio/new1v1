from datetime import datetime, timedelta

from fastapi import APIRouter, Depends

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_OBJ
from app.models import AppUser
from app.schemas.app_user import AnchorApplyIn, AnchorApplyStatusOut
from app.schemas.base import Fail, Success

router = APIRouter()

ANCHOR_REAPPLY_COOLDOWN_HOURS = 24


@router.post("/anchor/apply", summary="申请成为主播", dependencies=[Depends(DependAppAuth)])
async def apply_anchor(req_in: AnchorApplyIn):
    app_user: AppUser = CTX_APP_USER_OBJ.get()

    # 已为主播
    if app_user.is_anchor:
        return Fail(code=400, msg="您已经是主播")

    # 已有待审核申请
    if app_user.anchor_apply_status == "pending":
        return Fail(code=400, msg="您已有待审核的申请，请耐心等待")

    # 驳回冷却期
    if app_user.anchor_apply_status == "rejected" and app_user.anchor_reviewed_at:
        cooldown_deadline = app_user.anchor_reviewed_at + timedelta(hours=ANCHOR_REAPPLY_COOLDOWN_HOURS)
        if datetime.now() < cooldown_deadline:
            remaining_hours = int((cooldown_deadline - datetime.now()).total_seconds() / 3600) + 1
            return Fail(
                code=400,
                msg=f"距离上次驳回需等待 {ANCHOR_REAPPLY_COOLDOWN_HOURS} 小时后再申请（还剩 {remaining_hours} 小时）",
            )

    await AppUser.filter(id=app_user.id).update(
        anchor_intro=req_in.intro,
        anchor_tags=req_in.tags or [],
        anchor_call_price=req_in.call_price,
        anchor_apply_status="pending",
        anchor_apply_at=datetime.now(),
        anchor_reject_reason=None,
        anchor_reviewed_at=None,
    )
    return Success(data={"msg": "申请已提交，请等待审核"})


@router.get("/anchor/apply/status", summary="查询申请状态", dependencies=[Depends(DependAppAuth)])
async def get_apply_status():
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if app_user.is_anchor:
        status = "approved"
    else:
        status = (app_user.anchor_apply_status or "none").strip() or "none"
    if status not in {"none", "pending", "approved", "rejected"}:
        status = "none"

    return Success(
        data=AnchorApplyStatusOut(
            status=status,
            apply_at=app_user.anchor_apply_at,
            reject_reason=app_user.anchor_reject_reason,
            anchor_id=app_user.id if status == "approved" else None,
            anchor_user_id=app_user.id if status == "approved" else None,
        ).model_dump()
    )
