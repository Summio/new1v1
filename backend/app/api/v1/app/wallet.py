import asyncio
from fastapi import APIRouter, Depends

from app.core.app_auth import DependAppAuth
from app.core.dependency import LimitCallback
from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.models import AppUser, RechargeOrder, WithdrawApply
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
from app.core.redis import get_redis
from tortoise.transactions import in_transaction

router = APIRouter()


@router.get("/wallet/balance", summary="查询余额", dependencies=[Depends(DependAppAuth)])
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


@router.post("/recharge/create", summary="创建充值订单", dependencies=[Depends(DependAppAuth)])
async def recharge_create(req_in: RechargeCreateIn):
    user_id = CTX_APP_USER_ID.get()

    # P27: 生成唯一订单号（UUID 后缀保证极低冲突概率，兜底重试）
    import uuid
    from datetime import datetime

    order_no = None
    for _ in range(3):
        candidate = f"R{datetime.now().strftime('%Y%m%d%H%M%S')}{uuid.uuid4().hex[:8].upper()}"
        exists = await RechargeOrder.filter(order_no=candidate).exists()
        if not exists:
            order_no = candidate
            break

    if not order_no:
        return Fail(code=500, msg="订单创建失败，请重试")

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


@router.post("/wallet/callback", summary="充值回调", dependencies=[Depends(DependAppAuth), Depends(LimitCallback)])
async def recharge_callback(order_no: str):
    """充值支付回调

    安全注意：
      - 生产环境必须接入微信支付/支付宝真实回调，验证签名
      - 此 Mock 回调仅在 ENABLE_MOCK_CALLBACK=true 且 DEBUG=true 时可用
      - Mock 模式下：直接给用户加钻石（仅用于本地开发测试）
    """
    from app.settings.config import settings

    if not settings.ENABLE_MOCK_CALLBACK:
        return Fail(code=503, msg="充值回调接口未开放，请使用真实支付渠道")

    # B-7: Redis 幂等键，防止支付网关重试导致重复加钻
    try:
        redis_client = await get_redis()
        key = f"recharge:callback:idempotent:{order_no}"
        if not await redis_client.set(key, "1", nx=True, ex=3600):
            return Fail(code=429, msg="订单正在处理中，请勿重复提交")
    except Exception as e:  # noqa: BLE001
        # H1 修复：Redis 不可用时降级，但记录日志供监控
        from app.log import logger
        logger.warning("recharge callback idempotency check degraded: {}", str(e))

    callback_user_id = CTX_APP_USER_ID.get()
    async with in_transaction() as conn:
        order = await RechargeOrder.filter(
            order_no=order_no, status="pending"
        ).using_db(conn).select_for_update().first()
        if not order:
            return Fail(code=404, msg="订单不存在或已处理")

        # P9 修复：校验订单归属，防止任意用户凭他人 order_no 加钻
        if order.user_id != callback_user_id:
            return Fail(code=403, msg="无权操作此订单")

        # 加钻石：同一事务内更新用户余额
        await AppUser.filter(id=order.user_id).using_db(conn).update(
            diamonds=AppUser.diamonds + order.amount
        )
        order.status = "paid"
        await order.save(using_db=conn, update_fields=["status"])

    # 事务已提交，获取更新后的余额并推送 WebSocket（fire-and-forget）
    updated_user = await AppUser.filter(id=order.user_id).first()
    if updated_user:
        asyncio.create_task(_ws_push_balance_update(
            user_id=int(order.user_id),
            coins=int(updated_user.coins),
            diamonds=int(updated_user.diamonds),
        ))

    return Success(data={"msg": "充值成功"})


@router.post("/withdraw/apply", summary="申请提现（扣钻石，冻结审核）", dependencies=[Depends(DependAppAuth)])
async def withdraw_apply(req_in: WithdrawApplyIn):
    user_id = CTX_APP_USER_ID.get()

    # P2-4: 提现幂等性——60 秒内同一用户不可重复提交
    try:
        redis_client = await get_redis()
        key = f"withdraw:idempotency:{user_id}"
        set_ok = await redis_client.set(key, "1", nx=True, ex=60)
        if not set_ok:
            return Fail(code=429, msg="请求过于频繁，请稍后再试")
    except Exception as e:  # noqa: BLE001
        # H1 修复：Redis 不可用时降级放行，但记录日志供监控
        from app.log import logger
        logger.warning("withdraw idempotency check degraded: {}", str(e))

    # P13-P15: 提现金额合法性校验
    if req_in.amount <= 0:
        return Fail(code=400, msg="提现金额必须大于 0")
    if req_in.amount < 100:
        return Fail(code=400, msg="单次提现金额不低于 100 钻石")
    # C2 修复：提现金额上限保护，防止单次全额提空
    if req_in.amount > 50000:
        return Fail(code=400, msg="单次提现金额不超过 50000 钻石")
    if not req_in.real_name or not req_in.real_name.strip():
        return Fail(code=400, msg="请填写完整的真实姓名")
    if not req_in.bank_name or not req_in.bank_name.strip():
        return Fail(code=400, msg="请填写完整的银行名称")
    if not req_in.account_no or not req_in.account_no.strip():
        return Fail(code=400, msg="请填写完整的银行账号")

    # H3 修复：所有业务逻辑在事务外执行，事务块内仅执行数据库操作，
    # 避免在 async with in_transaction() 块内 return 导致事务未正确提交/回滚
    try:
        async with in_transaction() as conn:
            # 加行锁，防止并发请求同时通过余额检查
            app_user = await AppUser.filter(id=user_id).using_db(conn).select_for_update().first()
            if not app_user:
                raise ValueError("用户不存在")
            if app_user.diamonds < req_in.amount:
                raise ValueError("余额不足")

            # 冻结钻石：减少可用 + 增加冻结
            await AppUser.filter(id=user_id).using_db(conn).update(
                diamonds=AppUser.diamonds - req_in.amount,
                frozen_diamonds=AppUser.frozen_diamonds + req_in.amount,
            )

            # 创建提现申请
            await WithdrawApply.create(
                user_id=user_id,
                amount=req_in.amount,
                bank_name=req_in.bank_name.strip(),
                account_no=req_in.account_no.strip(),
                real_name=req_in.real_name.strip(),
                status="pending",
                using_db=conn,
            )

            # 获取冻结后的最新余额
            updated_user = await AppUser.filter(id=user_id).using_db(conn).first()
            final_diamonds = updated_user.diamonds if updated_user else 0
            final_frozen = updated_user.frozen_diamonds if updated_user else 0
    except ValueError as ve:
        msg_map = {
            "用户不存在": (401, "用户不存在"),
            "余额不足": (501, "余额不足"),
        }
        code, msg = msg_map.get(str(ve), (400, str(ve)))
        return Fail(code=code, msg=msg)
    except Exception:
        return Fail(code=500, msg="提现申请失败，请稍后重试")

    return Success(
        data=WithdrawApplyOut(
            diamonds=final_diamonds,
            frozen_diamonds=final_frozen,
            msg="提现申请已提交，审核通过后到账",
        ).model_dump()
    )


@router.get("/wallet/transactions", summary="账单明细", dependencies=[Depends(DependAppAuth)])
async def wallet_transactions(type: str = "all", page: int = 1, page_size: int = 20):
    user_id = CTX_APP_USER_ID.get()

    # P22: page_size 上限保护
    page_size = min(max(1, page_size), 50)
    offset = max(0, (page - 1) * page_size)

    # P-2 修复：UNION ALL 合并所有表，单次 DB 查询 + ORDER BY 做分页，消除多次查询和内存排序
    from tortoise import Tortoise

    type_map = {
        "recharge": "'recharge'",
        "call": "'call'",
        "gift": "'gift'",
        "withdraw": "'withdraw'",
    }
    union_parts = []
    params: list = [user_id, user_id, user_id, user_id, user_id, user_id, user_id, user_id]

    # recharge
    if type in ("all", "recharge"):
        union_parts.append(
            "SELECT id, 'recharge' AS rec_type, amount, created_at, 1 AS is_income "
            "FROM recharge_orders WHERE user_id = ? AND status = 'paid'"
        )
        params.append(user_id)
        params.append("paid")

    # call
    if type in ("all", "call"):
        union_parts.append(
            "SELECT id, 'call' AS rec_type, COALESCE(total_fee, 0) AS amount, created_at, 0 AS is_income "
            "FROM call_records WHERE caller_id = ?"
        )

    # gift sent
    if type in ("all", "gift"):
        union_parts.append(
            "SELECT id, 'gift' AS rec_type, price AS amount, created_at, 0 AS is_income "
            "FROM gift_records WHERE sender_id = ?"
        )
        if type == "all":
            union_parts.append(
                "SELECT id, 'gift' AS rec_type, price AS amount, created_at, 1 AS is_income "
                "FROM gift_records WHERE receiver_id = ?"
            )

    # withdraw
    if type in ("all", "withdraw"):
        union_parts.append(
            "SELECT id, 'withdraw' AS rec_type, amount, created_at, 0 AS is_income "
            "FROM withdraw_applies WHERE user_id = ?"
        )

    if not union_parts:
        return Success(data=TransactionListOut(records=[], total=0, current=page, has_more=False).model_dump())

    # 内层：UNION + LIMIT/OFFSET（DB 层分页）
    inner_limit = page_size
    inner_offset = offset
    inner_sql = " UNION ALL ".join(union_parts)

    # R-1 修复：LIMIT/OFFSET 使用参数化查询，防止注入
    if not isinstance(inner_limit, int) or inner_limit <= 0:
        inner_limit = 50
    if not isinstance(inner_offset, int) or inner_offset < 0:
        inner_offset = 0
    full_sql = f"""
        SELECT id, rec_type, amount, created_at, is_income FROM (
            {inner_sql}
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?
        ) AS t
    """
    query_params = params + [inner_limit, inner_offset]

    # 单独查 total（不含分页）
    count_sql = f"SELECT COUNT(*) AS cnt FROM ({inner_sql}) AS cnt_tbl"
    # 重新构建 params（UNION 每个子句有独立 WHERE）
    count_params: list = []
    if type in ("all", "recharge"):
        count_params.extend([user_id, "paid"])
    if type in ("all", "call"):
        count_params.append(user_id)
    if type in ("all", "gift"):
        count_params.append(user_id)
        if type == "all":
            count_params.append(user_id)
    if type in ("all", "withdraw"):
        count_params.append(user_id)

    conn = Tortoise.get_connection("default")
    count_row = await conn.execute_query(count_sql, count_params)
    total = count_row.rows[0][0] if count_row.rows else 0

    rows = await conn.execute_query(full_sql, query_params)
    records = []
    for row in rows.rows:
        rec_id, rec_type, amount, created_at, is_income = row
        title_map = {"recharge": "充值", "call": "通话消费", "gift": "收到礼物" if is_income else "送礼物", "withdraw": "提现申请"}
        records.append(TransactionRecord(
            id=str(rec_id),
            type=rec_type,
            title=title_map.get(rec_type, rec_type),
            amount=int(amount) if amount else 0,
            is_income=bool(is_income),
            created_at=created_at.strftime("%Y-%m-%d %H:%M:%S") if created_at else "",
        ))

    has_more = total > offset + page_size
    return Success(data=TransactionListOut(
        records=records,
        total=total,
        current=page,
        has_more=has_more,
    ).model_dump())


# ===== WebSocket 推送辅助函数（fire-and-forget） =====

async def _ws_push_balance_update(
    user_id: int,
    coins: int,
    diamonds: int,
) -> None:
    try:
        from app.websocket import events as ws_events
        await ws_events.push_balance_update(
            user_id=user_id,
            coins=coins,
            diamonds=diamonds,
        )
    except Exception:  # noqa: BLE001
        pass
