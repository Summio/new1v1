from typing import List

from fastapi import APIRouter, Depends

from app.core.app_auth import DependAppAuth
from app.core.dependency import LimitCallback
from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.models import AppUser, CallRecord, GiftRecord, RechargeOrder, WithdrawApply
from app.schemas.app_api import (
    BalanceOut,
    RechargeCreateIn,
    RechargeCreateOut,
    TransactionListOut,
    TransactionRecord,
    WithdrawApplyIn,
    WithdrawApplyOut,
)
from app.schemas.base import Fail, Success

router = APIRouter()


@router.get("/wallet/balance", summary="查询余额", dependencies=[DependAppAuth])
async def wallet_balance():
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")
    return Success(
        data=BalanceOut(
            coins=app_user.coins,
            diamonds=app_user.diamonds,
            frozen_diamonds=app_user.frozen_diamonds,
        ).model_dump()
    )


@router.post("/recharge/create", summary="创建充值订单", dependencies=[DependAppAuth])
async def recharge_create(req_in: RechargeCreateIn):
    user_id = CTX_APP_USER_ID.get()

    # 生成订单号
    import uuid
    from datetime import datetime
    order_no = f"R{datetime.now().strftime('%Y%m%d%H%M%S')}{uuid.uuid4().hex[:8].upper()}"

    await RechargeOrder.create(
        user_id=user_id,
        order_no=order_no,
        amount=req_in.amount,
        status="pending",
        pay_channel=req_in.pay_channel,
    )

    # TODO: 生产环境应接入微信支付/支付宝真实统一下单接口，此处为占位实现
    pay_url = None
    if req_in.pay_channel == "wx":
        pay_url = f"https://api.mch.weixin.qq.com/pay/unifiedorder?out_trade_no={order_no}"
    elif req_in.pay_channel == "alipay":
        pay_url = f"https://openapi.alipay.com/gateway.do?out_trade_no={order_no}"

    return Success(
        data=RechargeCreateOut(
            order_no=order_no,
            pay_url=pay_url,
            msg="订单创建成功，请完成支付",
        ).model_dump()
    )


@router.post("/wallet/callback", summary="充值回调（Mock: 直接加钻石）", dependencies=[DependAppAuth, Depends(LimitCallback)])
async def recharge_callback(order_no: str):
    """Mock 支付回调：直接给用户加钻石

    TODO(@pending): 当前为 Mock 实现，存在以下安全风险：
      1. 订单归属未校验（任意已登录用户可凭他人 order_no 加钻石）
      2. 无支付签名验证
      3. 无幂等性保障（极端并发下可能重复加钻）
    待接入微信支付/支付宝真实统一下单接口后，必须：
      - 验证回调签名（使用支付平台公钥验签）
      - 校验订单金额与状态
      - 使用数据库事务保证幂等
    """
    order = await RechargeOrder.filter(order_no=order_no, status="pending").first()
    if not order:
        return Fail(code=404, msg="订单不存在或已处理")
    if order.status == "paid":
        return Success(data={"msg": "订单已处理"})

    # 加钻石
    await AppUser.filter(id=order.user_id).update(
        diamonds=AppUser.diamonds + order.amount
    )
    order.status = "paid"
    await order.save(update_fields=["status"])

    return Success(data={"msg": "充值成功"})


@router.post("/withdraw/apply", summary="申请提现（扣钻石，冻结审核）", dependencies=[DependAppAuth])
async def withdraw_apply(req_in: WithdrawApplyIn):
    user_id = CTX_APP_USER_ID.get()
    app_user: AppUser = CTX_APP_USER_OBJ.get()

    if not app_user:
        return Fail(code=401, msg="用户不存在")

    # 冻结钻石，而非直接扣减（审核拒绝后可解冻）
    if app_user.diamonds < req_in.amount:
        return Fail(code=501, msg="余额不足")

    # 原子冻结：钻石减少 + 冻结钻石增加
    updated = await AppUser.filter(id=user_id, diamonds__gte=req_in.amount).update(
        diamonds=AppUser.diamonds - req_in.amount,
        frozen_diamonds=AppUser.frozen_diamonds + req_in.amount,
    )
    if updated == 0:
        return Fail(code=501, msg="余额不足，请稍后重试")

    # 创建提现申请
    await WithdrawApply.create(
        user_id=user_id,
        amount=req_in.amount,
        bank_name=req_in.bank_name,
        account_no=req_in.account_no,
        real_name=req_in.real_name,
        status="pending",
    )

    # 获取冻结后的最新钻石余额
    updated_user = await AppUser.filter(id=user_id).first()

    return Success(
        data=WithdrawApplyOut(
            diamonds=updated_user.diamonds if updated_user else 0,
            frozen_diamonds=updated_user.frozen_diamonds if updated_user else 0,
            msg="提现申请已提交，审核通过后到账",
        ).model_dump()
    )


@router.get("/wallet/transactions", summary="账单明细", dependencies=[DependAppAuth])
async def wallet_transactions(type: str = "all", page: int = 1, page_size: int = 20):
    user_id = CTX_APP_USER_ID.get()

    all_records: List[TransactionRecord] = []

    # 根据类型定向查询（避免加载全部表）
    if type in ("all", "recharge"):
        recharges = await RechargeOrder.filter(user_id=user_id, status="paid").order_by("-created_at").limit(500)
        for r in recharges:
            all_records.append(TransactionRecord(
                id=str(r.id),
                type="recharge",
                title="充值",
                amount=r.amount,
                is_income=True,
                created_at=r.created_at.strftime("%Y-%m-%d %H:%M:%S") if r.created_at else "",
            ))

    if type in ("all", "call"):
        calls = await CallRecord.filter(caller_id=user_id).order_by("-created_at").limit(500)
        for c in calls:
            all_records.append(TransactionRecord(
                id=str(c.id),
                type="call",
                title="通话消费",
                amount=c.total_fee,
                is_income=False,
                created_at=c.created_at.strftime("%Y-%m-%d %H:%M:%S") if c.created_at else "",
            ))

    if type in ("all", "gift"):
        gifts = await GiftRecord.filter(sender_id=user_id).order_by("-created_at").limit(500)
        for g in gifts:
            all_records.append(TransactionRecord(
                id=str(g.id),
                type="gift",
                title="送礼物",
                amount=g.price,
                is_income=False,
                created_at=g.created_at.strftime("%Y-%m-%d %H:%M:%S") if g.created_at else "",
            ))

    if type in ("all", "withdraw"):
        withdraws = await WithdrawApply.filter(user_id=user_id).order_by("-created_at").limit(500)
        for w in withdraws:
            all_records.append(TransactionRecord(
                id=str(w.id),
                type="withdraw",
                title="提现申请",
                amount=w.amount,
                is_income=False,
                created_at=w.created_at.strftime("%Y-%m-%d %H:%M:%S") if w.created_at else "",
            ))

    # 按时间倒序（内存排序，数据量受各表 limit=500 约束，最多约 2000 条）
    all_records.sort(key=lambda x: x.created_at, reverse=True)

    # 按 type 过滤
    if type == "income":
        all_records = [r for r in all_records if r.is_income]
    elif type == "expense":
        all_records = [r for r in all_records if not r.is_income]

    # 分页
    total = len(all_records)
    start = max(0, (page - 1) * page_size)
    end = start + page_size
    page_records = all_records[start:end]

    return Success(data=TransactionListOut(
        records=page_records,
        total=total,
        current=page,
        has_more=end < total,
    ).model_dump())
