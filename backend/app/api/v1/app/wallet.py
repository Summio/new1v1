import asyncio
import json
from pathlib import Path

from fastapi import APIRouter, Depends, File, UploadFile
from tortoise.expressions import F
from tortoise.transactions import in_transaction

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.core.dependency import LimitCallback
from app.core.redis import get_redis
from app.core.time_utils import now_local_naive
from app.models import (
    AppUser,
    RechargeOrder,
    SystemConfig,
    WithdrawAccount,
    WithdrawApply,
)
from app.schemas.app_api import (
    BalanceOut,
    RechargeCreateIn,
    RechargeCreateOut,
    TransactionListOut,
    TransactionRecord,
    WithdrawAccountIn,
    WithdrawAccountOut,
    WithdrawApplyIn,
    WithdrawApplyOut,
)
from app.schemas.base import Fail, Success
from app.services.balance_event_service import publish_balance_changed
from app.services.gift_income_service import decimal_to_float_2
from app.settings.config import settings
from app.utils.media_url import to_relative_media_url
from app.utils.upload_files import (
    UploadValidationError,
    read_validated_image_upload,
    save_upload_content,
)

router = APIRouter()
_ALLOWED_IMAGE_SUFFIX = {".jpg", ".jpeg", ".png", ".webp"}


def parse_withdraw_packages(config_value: str | None) -> list[dict]:
    try:
        data = json.loads(config_value or "[]")
    except (json.JSONDecodeError, ValueError):
        return []
    if not isinstance(data, list):
        return []
    packages = []
    for item in data:
        if not isinstance(item, dict):
            continue
        try:
            diamonds = int(item.get("diamonds") or 0)
            amount = int(item.get("amount") or 0)
        except (TypeError, ValueError):
            continue
        if diamonds <= 0 or amount <= 0:
            continue
        packages.append({"diamonds": diamonds, "amount": amount})
    return packages


async def is_configured_withdraw_amount(amount: int) -> bool:
    config_value = await SystemConfig.get_value("withdraw_packages", "[]")
    packages = parse_withdraw_packages(config_value)
    if not packages:
        return False
    return any(item["diamonds"] == amount for item in packages)


def dump_withdraw_account(account: WithdrawAccount | None) -> WithdrawAccountOut:
    if not account:
        return WithdrawAccountOut()
    return WithdrawAccountOut(
        real_name=account.real_name or "",
        account_no=account.account_no or "",
        payment_qr_code=to_relative_media_url(account.payment_qr_code),
        has_account=True,
        status=account.status or "pending",
        review_remark=account.review_remark or "",
        reviewed_at=account.reviewed_at,
        can_withdraw=account.status == "approved",
    )


def withdraw_account_payload_changed(
    account: WithdrawAccount,
    *,
    real_name: str,
    account_no: str,
    payment_qr_code: str,
) -> bool:
    return (
        (account.real_name or "") != real_name
        or (account.account_no or "") != account_no
        or to_relative_media_url(account.payment_qr_code) != payment_qr_code
    )


@router.get("/wallet/balance", summary="查询余额", dependencies=[Depends(DependAppAuth)])
async def wallet_balance():
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")
    token_names = await SystemConfig.get_all_as_dict()
    return Success(
        data=BalanceOut(
            coins=decimal_to_float_2(app_user.coins),
            diamonds=decimal_to_float_2(app_user.diamonds),
            frozen_diamonds=decimal_to_float_2(app_user.frozen_diamonds),
            coin_name=token_names.get("coin_name", "金币"),
            diamond_name=token_names.get("diamond_name", "钻石"),
        ).model_dump()
    )


@router.post("/recharge/create", summary="创建充值订单", dependencies=[Depends(DependAppAuth)])
async def recharge_create(req_in: RechargeCreateIn):
    user_id = CTX_APP_USER_ID.get()

    # P27: 生成唯一订单号（UUID 后缀保证极低冲突概率，兜底重试）
    import uuid

    order_no = None
    for _ in range(3):
        candidate = f"R{now_local_naive().strftime('%Y%m%d%H%M%S')}{uuid.uuid4().hex[:8].upper()}"
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
      - Mock 模式下：直接给用户加金币（仅用于本地开发测试）
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
        order = (
            await RechargeOrder.filter(order_no=order_no, status="pending").using_db(conn).select_for_update().first()
        )
        if not order:
            return Fail(code=404, msg="订单不存在或已处理")

        # P9 修复：校验订单归属，防止任意用户凭他人 order_no 加钻
        if order.user_id != callback_user_id:
            return Fail(code=403, msg="无权操作此订单")

        # 加金币：同一事务内更新用户余额
        await AppUser.filter(id=order.user_id).using_db(conn).update(coins=F("coins") + order.amount)
        order.status = "paid"
        await order.save(using_db=conn, update_fields=["status"])

    # 事务已提交，获取更新后的余额并推送 WebSocket（fire-and-forget）
    asyncio.create_task(_ws_push_balance_update(user_id=int(order.user_id), source="recharge"))

    return Success(data={"msg": "充值成功"})


@router.get("/withdraw/account", summary="获取提现账户", dependencies=[Depends(DependAppAuth)])
async def withdraw_account_get():
    user_id = CTX_APP_USER_ID.get()
    account = await WithdrawAccount.filter(user_id=user_id).first()
    return Success(data=dump_withdraw_account(account).model_dump())


@router.post("/withdraw/account", summary="提交提现账户审核", dependencies=[Depends(DependAppAuth)])
async def withdraw_account_save(req_in: WithdrawAccountIn):
    user_id = CTX_APP_USER_ID.get()
    real_name = req_in.real_name.strip()
    account_no = req_in.account_no.strip()
    payment_qr_code = to_relative_media_url(req_in.payment_qr_code)
    if not real_name:
        return Fail(code=400, msg="请填写真实姓名")
    if not account_no:
        return Fail(code=400, msg="请填写支付宝账号")
    if not payment_qr_code:
        return Fail(code=400, msg="请上传收款码")

    account = await WithdrawAccount.filter(user_id=user_id).first()
    if account:
        if account.status == "pending":
            return Fail(code=400, msg="提现账户待审核中，请勿重复提交")
        changed = withdraw_account_payload_changed(
            account,
            real_name=real_name,
            account_no=account_no,
            payment_qr_code=payment_qr_code,
        )
        if account.status == "approved" and not changed:
            return Success(data=dump_withdraw_account(account).model_dump(), msg="提现账户已通过审核")
        account.real_name = real_name
        account.account_no = account_no
        account.payment_qr_code = payment_qr_code
        account.status = "pending"
        account.reviewed_by = None
        account.reviewed_at = None
        account.review_remark = ""
        await account.save(
            update_fields=[
                "real_name",
                "account_no",
                "payment_qr_code",
                "status",
                "reviewed_by",
                "reviewed_at",
                "review_remark",
            ]
        )
    else:
        account = await WithdrawAccount.create(
            user_id=user_id,
            real_name=real_name,
            account_no=account_no,
            payment_qr_code=payment_qr_code,
            status="pending",
        )
    return Success(data=dump_withdraw_account(account).model_dump(), msg="提现账户已提交审核")


@router.post("/withdraw/upload-qr-code", summary="上传提现收款码", dependencies=[Depends(DependAppAuth)])
async def withdraw_upload_qr_code(file: UploadFile = File(...)):
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")
    try:
        suffix, content = await read_validated_image_upload(
            file,
            allowed_suffixes=_ALLOWED_IMAGE_SUFFIX,
            invalid_suffix_message="仅支持 jpg/jpeg/png/webp",
        )
    except UploadValidationError as exc:
        return Fail(code=exc.code, msg=exc.message)

    relative_url = save_upload_content(
        base_dir=settings.BASE_DIR,
        relative_dir=Path("withdraw_qr") / str(app_user.id),
        suffix=suffix,
        content=content,
    )
    return Success(data={"url": relative_url})


@router.post("/withdraw/apply", summary="申请提现（扣钻石，冻结审核）", dependencies=[Depends(DependAppAuth)])
async def withdraw_apply(req_in: WithdrawApplyIn):
    user_id = CTX_APP_USER_ID.get()

    # P13-P15: 提现金额合法性校验
    if req_in.amount <= 0:
        return Fail(code=400, msg="提现金额必须大于 0")
    config_value = await SystemConfig.get_value("withdraw_packages", "[]")
    if not parse_withdraw_packages(config_value):
        return Fail(code=400, msg="请先配置提现档位")
    if not await is_configured_withdraw_amount(req_in.amount):
        return Fail(code=400, msg="请选择有效的提现档位")

    account = await WithdrawAccount.filter(user_id=user_id, status="approved").first()
    if not account:
        return Fail(code=400, msg="请先提交并通过提现账户审核")

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
                diamonds=F("diamonds") - req_in.amount,
                frozen_diamonds=F("frozen_diamonds") + req_in.amount,
            )

            # 创建提现申请
            await WithdrawApply.create(
                user_id=user_id,
                amount=req_in.amount,
                bank_name="支付宝",
                account_no=account.account_no,
                real_name=account.real_name,
                payment_qr_code=account.payment_qr_code,
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
            diamonds=decimal_to_float_2(final_diamonds),
            frozen_diamonds=decimal_to_float_2(final_frozen),
            msg="提现申请已提交，处理通过后到账",
        ).model_dump()
    )


@router.get("/wallet/transactions", summary="账单明细", dependencies=[Depends(DependAppAuth)])
async def wallet_transactions(type: str = "all", page: int = 1, page_size: int = 20):
    user_id = CTX_APP_USER_ID.get()

    # P22: page_size 上限保护
    page_size = min(max(1, page_size), 50)
    offset = max(0, (page - 1) * page_size)

    # P-2 修复：UNION ALL 合并所有表，单次 DB 查询 + ORDER BY 做分页，消除多次查询和内存排序

    # 不依赖硬编码别名（如 default），直接使用模型绑定的实际连接
    conn = RechargeOrder._meta.db
    if conn is None:
        return Fail(code=500, msg="数据库连接未初始化")

    # 兼容不同驱动参数占位符（MySQL: %s，SQLite: ?）
    placeholder = "%s" if "mysql" in conn.__class__.__module__.lower() else "?"

    union_parts = []
    base_params: list = []

    # recharge
    if type in ("all", "recharge", "coins"):
        union_parts.append(
            f"SELECT id, 'recharge' AS rec_type, amount, created_at, 1 AS is_income, "
            f"NULL AS counterparty_user_id, '' AS gift_name, '' AS status "
            f"FROM recharge_order WHERE user_id = {placeholder} AND status = 'paid'"
        )
        base_params.append(user_id)

    # call expense (coins)
    if type in ("all", "call", "coins"):
        union_parts.append(
            f"SELECT id, 'call' AS rec_type, COALESCE(total_fee, 0) AS amount, created_at, 0 AS is_income, "
            f"callee_id AS counterparty_user_id, '' AS gift_name, '' AS status "
            f"FROM call_record WHERE caller_id = {placeholder}"
        )
        base_params.append(user_id)

    # call income (diamonds)
    if type in ("all", "call", "diamonds"):
        union_parts.append(
            f"SELECT id, 'call' AS rec_type, COALESCE(certified_user_income_diamonds, 0) AS amount, created_at, 1 AS is_income, "
            f"CASE WHEN caller_id = {placeholder} THEN callee_id ELSE caller_id END AS counterparty_user_id, "
            f"'' AS gift_name, '' AS status "
            f"FROM call_record WHERE income_certified_user_id = {placeholder} AND COALESCE(certified_user_income_diamonds, 0) > 0"
        )
        base_params.append(user_id)
        base_params.append(user_id)

    # gift sent (coins expense)
    if type in ("all", "gift", "coins"):
        union_parts.append(
            f"SELECT id, 'gift' AS rec_type, total_price AS amount, created_at, 0 AS is_income, "
            f"receiver_id AS counterparty_user_id, gift_name AS gift_name, '' AS status "
            f"FROM gift_record WHERE sender_id = {placeholder}"
        )
        base_params.append(user_id)

    # gift receive (diamonds income)
    if type in ("all", "diamonds"):
        union_parts.append(
            f"SELECT id, 'gift' AS rec_type, certified_user_income_diamonds AS amount, created_at, 1 AS is_income, "
            f"sender_id AS counterparty_user_id, gift_name AS gift_name, '' AS status "
            f"FROM gift_record WHERE receiver_id = {placeholder}"
        )
        base_params.append(user_id)

    # im text sent (coins expense)
    if type in ("all", "im_text", "coins"):
        union_parts.append(
            f"SELECT id, 'im_text' AS rec_type, price AS amount, created_at, 0 AS is_income, "
            f"receiver_id AS counterparty_user_id, '' AS gift_name, '' AS status "
            f"FROM im_text_message_charge_record WHERE sender_id = {placeholder} AND status = 'charged'"
        )
        base_params.append(user_id)

    # im text receive (diamonds income)
    if type in ("all", "im_text", "diamonds"):
        union_parts.append(
            f"SELECT id, 'im_text' AS rec_type, certified_user_income_diamonds AS amount, created_at, 1 AS is_income, "
            f"sender_id AS counterparty_user_id, '' AS gift_name, '' AS status "
            f"FROM im_text_message_charge_record WHERE receiver_id = {placeholder} "
            f"AND status = 'charged' AND certified_user_income_diamonds > 0"
        )
        base_params.append(user_id)

    # withdraw
    if type in ("all", "withdraw", "diamonds"):
        union_parts.append(
            f"SELECT id, 'withdraw' AS rec_type, amount, created_at, 0 AS is_income, "
            f"NULL AS counterparty_user_id, account_no AS gift_name, "
            f"status AS status "
            f"FROM withdraw_apply WHERE user_id = {placeholder}"
        )
        base_params.append(user_id)

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
        SELECT id, rec_type, amount, created_at, is_income, counterparty_user_id, gift_name, status FROM (
            {inner_sql}
            ORDER BY created_at DESC
            LIMIT {placeholder} OFFSET {placeholder}
        ) AS t
    """
    query_params = base_params + [inner_limit, inner_offset]

    # 单独查 total（不含分页）
    count_sql = f"SELECT COUNT(*) AS cnt FROM ({inner_sql}) AS cnt_tbl"
    count_params = list(base_params)

    def _extract_rows(query_result):
        # MySQL 常见返回: (rowcount, rows)；部分驱动返回带 .rows 的对象
        if isinstance(query_result, tuple):
            if len(query_result) >= 2 and isinstance(query_result[1], (list, tuple)):
                return query_result[1]
            if len(query_result) == 1 and isinstance(query_result[0], (list, tuple)):
                return query_result[0]
            return []
        rows_attr = getattr(query_result, "rows", None)
        if rows_attr is not None:
            return rows_attr
        if isinstance(query_result, list):
            return query_result
        return []

    count_result = await conn.execute_query(count_sql, count_params)
    count_rows = _extract_rows(count_result)
    total = 0
    if count_rows:
        first_row = count_rows[0]
        if isinstance(first_row, dict):
            total = int(first_row.get("cnt") or 0)
        elif isinstance(first_row, (list, tuple)):
            total = int(first_row[0]) if first_row else 0

    query_result = await conn.execute_query(full_sql, query_params)
    rows = _extract_rows(query_result)
    counterparty_ids: set[int] = set()
    for row in rows:
        counterparty_id = row.get("counterparty_user_id") if isinstance(row, dict) else row[5]
        if counterparty_id is None:
            continue
        try:
            counterparty_ids.add(int(counterparty_id))
        except (TypeError, ValueError):
            continue

    user_name_map: dict[int, str] = {}
    if counterparty_ids:
        users = await AppUser.filter(id__in=list(counterparty_ids)).values("id", "nickname")
        user_name_map = {int(item["id"]): str(item.get("nickname") or "") for item in users}

    records = []
    for row in rows:
        if isinstance(row, dict):
            rec_id = row.get("id")
            rec_type = row.get("rec_type")
            amount = row.get("amount")
            created_at = row.get("created_at")
            is_income = row.get("is_income")
            counterparty_id = row.get("counterparty_user_id")
            gift_name = row.get("gift_name")
            status = row.get("status")
        else:
            rec_id, rec_type, amount, created_at, is_income, counterparty_id, gift_name, status = row

        counterparty_name = ""
        if counterparty_id is not None:
            try:
                counterparty_name = user_name_map.get(int(counterparty_id), "")
            except (TypeError, ValueError):
                counterparty_name = ""
        if rec_type == "withdraw":
            counterparty_name = str(gift_name or "支付宝")

        title_map = {
            "recharge": "充值",
            "call": "通话收益" if is_income else "通话消费",
            "gift": (
                (f"收到礼物·{gift_name}" if gift_name else "收到礼物")
                if is_income
                else (f"送礼物·{gift_name}" if gift_name else "送礼物")
            ),
            "im_text": "文字聊天收益" if is_income else "文字聊天",
            "withdraw": "提现申请",
        }
        if hasattr(created_at, "strftime"):
            created_at_text = created_at.strftime("%Y-%m-%d %H:%M:%S")
        else:
            created_at_text = str(created_at) if created_at else ""
        records.append(
            TransactionRecord(
                id=str(rec_id),
                type=str(rec_type or ""),
                title=title_map.get(rec_type, rec_type),
                amount=decimal_to_float_2(amount),
                is_income=bool(is_income),
                created_at=created_at_text,
                counterparty_name=counterparty_name,
                status=str(status or ""),
            )
        )

    has_more = total > offset + page_size
    return Success(
        data=TransactionListOut(
            records=records,
            total=total,
            current=page,
            has_more=has_more,
        ).model_dump()
    )


# ===== WebSocket 推送辅助函数（fire-and-forget） =====


async def _ws_push_balance_update(
    user_id: int,
    source: str,
) -> None:
    try:
        await publish_balance_changed(int(user_id), source=source)
    except Exception:  # noqa: BLE001
        pass
