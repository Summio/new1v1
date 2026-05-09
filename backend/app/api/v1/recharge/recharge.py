from fastapi import APIRouter, Query
from tortoise.expressions import F, Q
from tortoise.transactions import in_transaction

from app.core.time_utils import now_local_naive
from app.models import AppUser, RechargeOrder
from app.schemas.app_api import RechargeListItem, RechargeReviewIn
from app.schemas.base import Fail, Success, SuccessExtra

router = APIRouter()


@router.get("/list", summary="充值订单列表")
async def recharge_list(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    status: str = Query("", description="状态筛选：pending/paid/refunded"),
    user_id: int = Query(None, description="用户ID"),
    order_no: str = Query("", description="订单号"),
    pay_channel: str = Query("", description="支付渠道 wx/alipay"),
):
    q = Q()
    if status:
        q &= Q(status=status.strip())
    if user_id:
        q &= Q(user_id=user_id)
    if order_no:
        q &= Q(order_no__contains=order_no.strip())
    if pay_channel:
        q &= Q(pay_channel=pay_channel.strip())

    total = await RechargeOrder.filter(q).count()
    records = await RechargeOrder.filter(q).order_by("-created_at").offset((page - 1) * page_size).limit(page_size)

    user_ids = list({int(row.user_id) for row in records})
    user_map: dict[int, str] = {}
    if user_ids:
        users = await AppUser.filter(id__in=user_ids).all()
        user_map = {
            int(user.id): ((user.nickname or "").strip() or (user.phone or "").strip() or f"用户{user.id}")
            for user in users
        }

    items = []
    for row in records:
        items.append(
            RechargeListItem(
                id=row.id,
                user_id=int(row.user_id),
                amount=int(row.amount),
                order_no=row.order_no or "",
                status=row.status or "pending",
                pay_channel=(row.pay_channel or "").strip(),
                created_at=row.created_at,
                paid_at=row.paid_at,
                username=user_map.get(int(row.user_id)),
            )
        )

    return SuccessExtra(
        data=[item.model_dump(mode="json") for item in items], total=total, page=page, page_size=page_size
    )


@router.post("/review", summary="充值订单处理")
async def recharge_review(req_in: RechargeReviewIn):
    action = req_in.action.strip().lower()
    if action != "mark_paid":
        return Fail(code=400, msg="action 必须为 mark_paid")

    async with in_transaction() as conn:
        order = await RechargeOrder.filter(id=req_in.order_id).using_db(conn).first()
        if not order:
            return Fail(code=404, msg="充值订单不存在")

        if order.status == "paid":
            return Success(msg="订单已是已支付状态")
        if order.status != "pending":
            return Fail(code=400, msg=f"该订单状态为「{order.status}」，无法标记已支付")

        await AppUser.filter(id=order.user_id).using_db(conn).update(
            coins=F("coins") + order.amount,
        )
        order.status = "paid"
        order.paid_at = now_local_naive()
        await order.save(using_db=conn, update_fields=["status", "paid_at"])
        return Success(msg="已标记为支付成功")
