from datetime import date, datetime
from decimal import Decimal
from typing import Any

from fastapi import APIRouter, Query

from app.models import AppUser, RechargeOrder
from app.schemas.base import Fail, SuccessExtra
from app.services.gift_income_service import decimal_to_float_2

router = APIRouter()

_ALLOWED_ASSET_TYPES = {"coins", "diamonds"}
_ALLOWED_DIRECTIONS = {"all", "income", "expense"}
_ALLOWED_BIZ_TYPES = {
    "recharge",
    "call",
    "call_fee",
    "gift",
    "gift_fee",
    "im_text",
    "withdraw",
    "token_adjust",
}


def _parse_dt(dt_str: str, field_name: str) -> datetime:
    raw = (dt_str or "").strip()
    if not raw:
        raise ValueError(f"{field_name} 不能为空")
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"{field_name} 格式错误，要求 YYYY-MM-DD HH:mm:ss 或 ISO8601") from exc


def _format_dt(value: datetime | date | str | None) -> str:
    if not value:
        return ""
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(value, date):
        return value.isoformat()
    return str(value)


def _row_value(row: dict[str, Any] | tuple[Any, ...], key: str, index: int) -> Any:
    if isinstance(row, dict):
        return row.get(key)
    return row[index] if len(row) > index else None


def _extract_rows(query_result):
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


def _int_or_none(value) -> int | None:
    try:
        parsed = int(value or 0)
    except (TypeError, ValueError):
        return None
    return parsed if parsed > 0 else None


def _user_brief(user_map: dict[int, AppUser], user_id: int | None, fallback: str = "") -> dict:
    uid = int(user_id or 0)
    if uid <= 0:
        return {"id": None, "nickname": fallback, "phone": ""}
    user = user_map.get(uid)
    if not user:
        return {"id": uid, "nickname": f"用户{uid}", "phone": ""}
    return {
        "id": uid,
        "nickname": (user.nickname or user.phone or f"用户{uid}"),
        "phone": user.phone or "",
    }


async def _load_user_map(user_ids: set[int]) -> dict[int, AppUser]:
    normalized_ids = [int(uid) for uid in user_ids if int(uid or 0) > 0]
    if not normalized_ids:
        return {}
    users = await AppUser.filter(id__in=normalized_ids).all()
    return {int(user.id): user for user in users}


def _amount(value) -> float:
    if isinstance(value, Decimal):
        return decimal_to_float_2(value)
    return decimal_to_float_2(value or 0)


def _placeholder_for(conn) -> str:
    return "%s" if "mysql" in conn.__class__.__module__.lower() else "?"


def _business_ledger_union_sql() -> str:
    return """
        SELECT
            'recharge' AS ledger_key,
            'recharge' AS biz_type,
            id AS biz_id,
            id AS sort_id,
            user_id AS user_id,
            NULL AS related_user_id,
            'coins' AS asset_type,
            'income' AS direction,
            1 AS is_income,
            amount AS amount,
            COALESCE(paid_at, created_at) AS event_time,
            status AS status,
            NULL AS operator_user_id,
            '' AS operator_username,
            '' AS remark,
            '充值' AS title
        FROM recharge_order
        WHERE status = 'paid' AND COALESCE(amount, 0) > 0

        UNION ALL

        SELECT
            'call_expense' AS ledger_key,
            'call' AS biz_type,
            id AS biz_id,
            id AS sort_id,
            COALESCE(payer_user_id, caller_id) AS user_id,
            CASE
                WHEN COALESCE(payer_user_id, caller_id) = caller_id THEN callee_id
                ELSE caller_id
            END AS related_user_id,
            'coins' AS asset_type,
            'expense' AS direction,
            0 AS is_income,
            total_fee AS amount,
            COALESCE(ended_at, created_at) AS event_time,
            status AS status,
            NULL AS operator_user_id,
            '' AS operator_username,
            COALESCE(end_reason, '') AS remark,
            '通话消费' AS title
        FROM call_record
        WHERE COALESCE(total_fee, 0) > 0

        UNION ALL

        SELECT
            'call_income' AS ledger_key,
            'call' AS biz_type,
            id AS biz_id,
            id AS sort_id,
            income_certified_user_id AS user_id,
            CASE
                WHEN COALESCE(payer_user_id, caller_id) = income_certified_user_id THEN
                    CASE WHEN caller_id = income_certified_user_id THEN callee_id ELSE caller_id END
                ELSE COALESCE(payer_user_id, caller_id)
            END AS related_user_id,
            'diamonds' AS asset_type,
            'income' AS direction,
            1 AS is_income,
            certified_user_income_diamonds AS amount,
            COALESCE(income_settled_at, created_at) AS event_time,
            status AS status,
            NULL AS operator_user_id,
            '' AS operator_username,
            '' AS remark,
            '通话收益' AS title
        FROM call_record
        WHERE income_certified_user_id IS NOT NULL
          AND COALESCE(certified_user_income_diamonds, 0) > 0

        UNION ALL

        SELECT
            'call_fee_payer' AS ledger_key,
            'call_fee' AS biz_type,
            id AS biz_id,
            id AS sort_id,
            COALESCE(payer_user_id, caller_id) AS user_id,
            CASE
                WHEN COALESCE(payer_user_id, caller_id) = caller_id THEN callee_id
                ELSE caller_id
            END AS related_user_id,
            'coins' AS asset_type,
            'expense' AS direction,
            0 AS is_income,
            service_fee_payer_actual_coins AS amount,
            COALESCE(service_fee_payer_settled_at, created_at) AS event_time,
            COALESCE(service_fee_payer_status, '') AS status,
            NULL AS operator_user_id,
            '' AS operator_username,
            '' AS remark,
            '通话手续费' AS title
        FROM call_record
        WHERE COALESCE(service_fee_payer_actual_coins, 0) > 0

        UNION ALL

        SELECT
            'call_fee_income' AS ledger_key,
            'call_fee' AS biz_type,
            id AS biz_id,
            id AS sort_id,
            income_certified_user_id AS user_id,
            CASE
                WHEN COALESCE(payer_user_id, caller_id) = income_certified_user_id THEN
                    CASE WHEN caller_id = income_certified_user_id THEN callee_id ELSE caller_id END
                ELSE COALESCE(payer_user_id, caller_id)
            END AS related_user_id,
            'diamonds' AS asset_type,
            'expense' AS direction,
            0 AS is_income,
            service_fee_income_actual_diamonds AS amount,
            COALESCE(service_fee_income_settled_at, created_at) AS event_time,
            COALESCE(service_fee_income_status, '') AS status,
            NULL AS operator_user_id,
            '' AS operator_username,
            '' AS remark,
            '通话收益手续费' AS title
        FROM call_record
        WHERE income_certified_user_id IS NOT NULL
          AND COALESCE(service_fee_income_actual_diamonds, 0) > 0

        UNION ALL

        SELECT
            'gift_expense' AS ledger_key,
            'gift' AS biz_type,
            id AS biz_id,
            id AS sort_id,
            sender_id AS user_id,
            receiver_id AS related_user_id,
            'coins' AS asset_type,
            'expense' AS direction,
            0 AS is_income,
            total_price AS amount,
            created_at AS event_time,
            '' AS status,
            NULL AS operator_user_id,
            '' AS operator_username,
            COALESCE(gift_name, '') AS remark,
            '送礼消费' AS title
        FROM gift_record
        WHERE COALESCE(total_price, 0) > 0

        UNION ALL

        SELECT
            'gift_income' AS ledger_key,
            'gift' AS biz_type,
            id AS biz_id,
            id AS sort_id,
            receiver_id AS user_id,
            sender_id AS related_user_id,
            'diamonds' AS asset_type,
            'income' AS direction,
            1 AS is_income,
            certified_user_income_diamonds AS amount,
            created_at AS event_time,
            '' AS status,
            NULL AS operator_user_id,
            '' AS operator_username,
            COALESCE(gift_name, '') AS remark,
            '礼物收益' AS title
        FROM gift_record
        WHERE COALESCE(certified_user_income_diamonds, 0) > 0

        UNION ALL

        SELECT
            'gift_fee' AS ledger_key,
            'gift_fee' AS biz_type,
            id AS biz_id,
            id AS sort_id,
            sender_id AS user_id,
            receiver_id AS related_user_id,
            'coins' AS asset_type,
            'expense' AS direction,
            0 AS is_income,
            service_fee_sender_actual_coins AS amount,
            COALESCE(service_fee_sender_settled_at, created_at) AS event_time,
            COALESCE(service_fee_sender_status, '') AS status,
            NULL AS operator_user_id,
            '' AS operator_username,
            COALESCE(gift_name, '') AS remark,
            '礼物手续费' AS title
        FROM gift_record
        WHERE COALESCE(service_fee_sender_actual_coins, 0) > 0

        UNION ALL

        SELECT
            'im_text_expense' AS ledger_key,
            'im_text' AS biz_type,
            id AS biz_id,
            id AS sort_id,
            sender_id AS user_id,
            receiver_id AS related_user_id,
            'coins' AS asset_type,
            'expense' AS direction,
            0 AS is_income,
            price AS amount,
            created_at AS event_time,
            status AS status,
            NULL AS operator_user_id,
            '' AS operator_username,
            '' AS remark,
            '文字聊天' AS title
        FROM im_text_message_charge_record
        WHERE status = 'charged' AND COALESCE(price, 0) > 0

        UNION ALL

        SELECT
            'im_text_income' AS ledger_key,
            'im_text' AS biz_type,
            id AS biz_id,
            id AS sort_id,
            receiver_id AS user_id,
            sender_id AS related_user_id,
            'diamonds' AS asset_type,
            'income' AS direction,
            1 AS is_income,
            certified_user_income_diamonds AS amount,
            created_at AS event_time,
            status AS status,
            NULL AS operator_user_id,
            '' AS operator_username,
            '' AS remark,
            '文字聊天收益' AS title
        FROM im_text_message_charge_record
        WHERE status = 'charged' AND COALESCE(certified_user_income_diamonds, 0) > 0

        UNION ALL

        SELECT
            'withdraw' AS ledger_key,
            'withdraw' AS biz_type,
            id AS biz_id,
            id AS sort_id,
            user_id AS user_id,
            NULL AS related_user_id,
            'diamonds' AS asset_type,
            'expense' AS direction,
            0 AS is_income,
            amount AS amount,
            created_at AS event_time,
            status AS status,
            NULL AS operator_user_id,
            '' AS operator_username,
            COALESCE(review_remark, '') AS remark,
            '提现申请' AS title
        FROM withdraw_apply
        WHERE COALESCE(amount, 0) > 0

        UNION ALL

        SELECT
            'token_adjust' AS ledger_key,
            'token_adjust' AS biz_type,
            id AS biz_id,
            id AS sort_id,
            app_user_id AS user_id,
            NULL AS related_user_id,
            asset_type AS asset_type,
            CASE WHEN action = 'increase' THEN 'income' ELSE 'expense' END AS direction,
            CASE WHEN action = 'increase' THEN 1 ELSE 0 END AS is_income,
            amount AS amount,
            created_at AS event_time,
            action AS status,
            operator_user_id AS operator_user_id,
            operator_username AS operator_username,
            COALESCE(reason, '') AS remark,
            CASE
                WHEN asset_type = 'coins' AND action = 'increase' THEN '后台增加金币'
                WHEN asset_type = 'coins' AND action = 'decrease' THEN '后台扣除金币'
                WHEN asset_type = 'diamonds' AND action = 'increase' THEN '后台增加钻石'
                WHEN asset_type = 'diamonds' AND action = 'decrease' THEN '后台扣除钻石'
                ELSE '后台调整'
            END AS title
        FROM app_user_token_adjust_record
        WHERE COALESCE(amount, 0) > 0
    """


@router.get("/list", summary="代币流水列表")
async def list_business_ledger(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    user_id: int | None = Query(None, ge=1, description="流水归属用户ID"),
    related_user_id: int | None = Query(None, ge=1, description="关联用户ID"),
    asset_type: str = Query("", description="资产类型 coins/diamonds"),
    direction: str = Query("all", description="方向 all/income/expense"),
    biz_type: str = Query("", description="业务类型"),
    biz_id: int | None = Query(None, ge=1, description="业务记录ID"),
    start_time: str = Query("", description="开始时间(事件时间起)"),
    end_time: str = Query("", description="结束时间(事件时间止)"),
):
    normalized_asset_type = (asset_type or "").strip().lower()
    if normalized_asset_type and normalized_asset_type not in _ALLOWED_ASSET_TYPES:
        return Fail(code=400, msg="asset_type 仅支持 coins/diamonds")

    normalized_direction = (direction or "all").strip().lower()
    if normalized_direction not in _ALLOWED_DIRECTIONS:
        return Fail(code=400, msg="direction 仅支持 all/income/expense")

    normalized_biz_type = (biz_type or "").strip().lower()
    if normalized_biz_type and normalized_biz_type not in _ALLOWED_BIZ_TYPES:
        return Fail(
            code=400,
            msg="biz_type 仅支持 recharge/call/call_fee/gift/gift_fee/im_text/withdraw/token_adjust",
        )

    try:
        started_at = _parse_dt(start_time, "start_time") if start_time else None
        ended_at = _parse_dt(end_time, "end_time") if end_time else None
    except ValueError as exc:
        return Fail(code=400, msg=str(exc))

    conn = RechargeOrder._meta.db
    if conn is None:
        return Fail(code=500, msg="数据库连接未初始化")

    placeholder = _placeholder_for(conn)
    where_parts = ["ledger.event_time IS NOT NULL"]
    filter_params: list[Any] = []
    if user_id is not None:
        where_parts.append(f"ledger.user_id = {placeholder}")
        filter_params.append(user_id)
    if related_user_id is not None:
        where_parts.append(f"ledger.related_user_id = {placeholder}")
        filter_params.append(related_user_id)
    if normalized_asset_type:
        where_parts.append(f"ledger.asset_type = {placeholder}")
        filter_params.append(normalized_asset_type)
    if normalized_direction != "all":
        where_parts.append(f"ledger.direction = {placeholder}")
        filter_params.append(normalized_direction)
    if normalized_biz_type:
        where_parts.append(f"ledger.biz_type = {placeholder}")
        filter_params.append(normalized_biz_type)
    if biz_id is not None:
        where_parts.append(f"ledger.biz_id = {placeholder}")
        filter_params.append(biz_id)
    if started_at is not None:
        where_parts.append(f"ledger.event_time >= {placeholder}")
        filter_params.append(started_at)
    if ended_at is not None:
        where_parts.append(f"ledger.event_time <= {placeholder}")
        filter_params.append(ended_at)

    union_sql = _business_ledger_union_sql()
    where_sql = " AND ".join(where_parts)
    count_sql = f"SELECT COUNT(*) AS cnt FROM ({union_sql}) AS ledger WHERE {where_sql}"
    page_offset = (page - 1) * page_size
    list_sql = f"""
        SELECT
            ledger_key,
            biz_type,
            biz_id,
            user_id,
            related_user_id,
            asset_type,
            direction,
            is_income,
            amount,
            event_time,
            status,
            operator_user_id,
            operator_username,
            remark,
            title
        FROM ({union_sql}) AS ledger
        WHERE {where_sql}
        ORDER BY event_time DESC, sort_id DESC
        LIMIT {placeholder} OFFSET {placeholder}
    """

    count_result = await conn.execute_query(count_sql, filter_params)
    count_rows = _extract_rows(count_result)
    total = 0
    if count_rows:
        first_row = count_rows[0]
        if isinstance(first_row, dict):
            total = int(first_row.get("cnt") or 0)
        elif isinstance(first_row, (list, tuple)):
            total = int(first_row[0]) if first_row else 0

    rows_result = await conn.execute_query(list_sql, filter_params + [page_size, page_offset])
    raw_rows = _extract_rows(rows_result)

    user_ids: set[int] = set()
    for row in raw_rows:
        row_user_id = _int_or_none(_row_value(row, "user_id", 3))
        row_related_user_id = _int_or_none(_row_value(row, "related_user_id", 4))
        if row_user_id:
            user_ids.add(row_user_id)
        if row_related_user_id:
            user_ids.add(row_related_user_id)
    user_map = await _load_user_map(user_ids)

    data = []
    for row in raw_rows:
        ledger_key = str(_row_value(row, "ledger_key", 0) or "")
        row_biz_type = str(_row_value(row, "biz_type", 1) or "")
        row_biz_id = int(_row_value(row, "biz_id", 2) or 0)
        row_user_id = _int_or_none(_row_value(row, "user_id", 3))
        row_related_user_id = _int_or_none(_row_value(row, "related_user_id", 4))
        row_asset_type = str(_row_value(row, "asset_type", 5) or "")
        row_direction = str(_row_value(row, "direction", 6) or "")
        row_is_income = bool(int(_row_value(row, "is_income", 7) or 0))
        row_amount = _amount(_row_value(row, "amount", 8))
        row_event_time = _format_dt(_row_value(row, "event_time", 9))
        row_status = str(_row_value(row, "status", 10) or "")
        row_operator_user_id = _int_or_none(_row_value(row, "operator_user_id", 11))
        row_operator_username = str(_row_value(row, "operator_username", 12) or "")
        row_remark = str(_row_value(row, "remark", 13) or "")
        row_title = str(_row_value(row, "title", 14) or "")

        related_fallback = "后台调整" if row_biz_type == "token_adjust" else "平台"
        data.append(
            {
                "id": f"{ledger_key}_{row_biz_id}",
                "biz_id": row_biz_id,
                "biz_type": row_biz_type,
                "title": row_title,
                "user_id": row_user_id,
                "user": _user_brief(user_map, row_user_id),
                "related_user_id": row_related_user_id,
                "related_user": _user_brief(user_map, row_related_user_id, fallback=related_fallback),
                "direction": row_direction,
                "is_income": row_is_income,
                "asset_type": row_asset_type,
                "amount": row_amount,
                "event_time": row_event_time,
                "created_at": row_event_time,
                "status": row_status,
                "operator_user_id": row_operator_user_id,
                "operator_username": row_operator_username,
                "remark": row_remark,
            }
        )

    return SuccessExtra(
        data=data,
        total=total,
        page=page,
        page_size=page_size,
        current=page,
        has_more=total > page * page_size,
    )
