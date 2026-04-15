from fastapi import APIRouter

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID
from app.models import Anchor, AppUser, Gift, GiftRecord
from app.schemas.app_api import GiftOut, GiftSendIn, GiftSendOut
from app.schemas.base import Fail, Success, SuccessExtra

router = APIRouter()


@router.get("/gift/list", summary="礼物列表")
async def gift_list():
    gifts = await Gift.filter(is_active=True).order_by("price")
    rows = [
        {
            "id": g.id,
            "name": g.name,
            "icon": g.icon,
            "price": g.price,
        }
        for g in gifts
    ]
    return SuccessExtra(rows=rows, total=len(rows), has_more=False)


@router.post("/gift/send", summary="发送礼物", dependencies=[DependAppAuth])
async def gift_send(req_in: GiftSendIn):
    sender_id = CTX_APP_USER_ID.get()

    # 查找礼物
    gift = await Gift.filter(id=req_in.gift_id, is_active=True).first()
    if not gift:
        return Fail(code=404, msg="礼物不存在或已下架")

    # 查找主播（需审批通过）
    anchor = await Anchor.filter(id=req_in.anchor_id, apply_status="approved").first()
    if not anchor:
        return Fail(code=404, msg="主播不存在")

    # 原子扣费：使用条件更新避免竞态（扣金币）
    updated = await AppUser.filter(id=sender_id, coins__gte=gift.price).update(
        coins=AppUser.coins - gift.price
    )
    if updated == 0:
        return Fail(code=501, msg="余额不足，请先充值")

    # 记录礼物
    await GiftRecord.create(
        sender_id=sender_id,
        receiver_id=anchor.app_user_id,
        gift_id=gift.id,
        gift_name=gift.name,
        price=gift.price,
    )

    # TODO: 通过 IM 下发自定义信令（信令发送由 IM 模块负责）

    # 获取扣费后最新金币余额
    sender = await AppUser.filter(id=sender_id).first()

    return Success(
        data=GiftSendOut(
            gift_name=gift.name,
            coins=sender.coins if sender else 0,
            msg="发送成功",
        ).model_dump()
    )
