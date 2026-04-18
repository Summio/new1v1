from datetime import datetime, timedelta

from fastapi import APIRouter, Depends

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.models import Anchor, AppUser
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
    existing_pending = await Anchor.filter(app_user_id=app_user.id, apply_status="pending").first()
    if existing_pending:
        return Fail(code=400, msg="您已有待审核的申请，请耐心等待")

    # 已有被驳回记录，更新信息重新提交
    existing = await Anchor.filter(app_user_id=app_user.id).first()
    if existing:
        # L-3 修复：驳回后需等待冷却期才可重新申请，防止频繁重试骚扰审核
        if existing.apply_status == "rejected" and existing.reviewed_at:
            cooldown_deadline = existing.reviewed_at + timedelta(hours=ANCHOR_REAPPLY_COOLDOWN_HOURS)
            if datetime.now() < cooldown_deadline:
                remaining_hours = int((cooldown_deadline - datetime.now()).total_seconds() / 3600) + 1
                return Fail(
                    code=400,
                    msg=f"距离上次驳回需等待 {ANCHOR_REAPPLY_COOLDOWN_HOURS} 小时后再申请（还剩 {remaining_hours} 小时）",
                )
        existing.intro = req_in.intro
        existing.tags = req_in.tags
        existing.call_price = req_in.call_price
        existing.apply_status = "pending"
        existing.apply_at = datetime.now()
        existing.reject_reason = None
        existing.reviewed_at = None
        await existing.save()
        return Success(data={"msg": "申请已更新，请等待审核"})

    # 新建申请
    await Anchor.create(
        app_user_id=app_user.id,
        intro=req_in.intro,
        tags=req_in.tags,
        call_price=req_in.call_price,
        avatar=app_user.avatar,
        apply_status="pending",
        apply_at=datetime.now(),
    )

    return Success(data={"msg": "申请已提交，请等待审核"})


@router.get("/anchor/apply/status", summary="查询申请状态", dependencies=[Depends(DependAppAuth)])
async def get_apply_status():
    app_user: AppUser = CTX_APP_USER_OBJ.get()

    anchor = await Anchor.filter(app_user_id=app_user.id).first()
    if not anchor:
        return Success(data=AnchorApplyStatusOut(status="none").model_dump())

    return Success(
        data=AnchorApplyStatusOut(
            status=anchor.apply_status,
            apply_at=anchor.apply_at,
            reject_reason=anchor.reject_reason,
            anchor_id=anchor.id if anchor.apply_status == "approved" else None,
        ).model_dump()
    )
