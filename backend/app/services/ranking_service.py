from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any

from tortoise.transactions import in_transaction

from app.core.redis import get_redis
from app.core.time_utils import now_local_naive, to_local_naive_for_db
from app.models import AppUser, RankingSnapshot, SystemConfig
from app.models.system_config import SYSTEM_CONFIG_CACHE_KEY
from app.services.customer_service import get_customer_service_user_id
from app.services.gift_income_service import decimal_to_float_2, quantize_decimal_2
from app.services.vip_service import vip_payload
from app.utils.media_url import to_relative_media_url

BOARD_CHARM = "charm"
BOARD_WEALTH = "wealth"
BOARD_INVITE = "invite"
PERIOD_DAY = "day"
PERIOD_WEEK = "week"
PERIOD_MONTH = "month"
VALID_BOARDS = {BOARD_CHARM, BOARD_WEALTH, BOARD_INVITE}
VALID_PERIODS = {PERIOD_DAY, PERIOD_WEEK, PERIOD_MONTH}
RANKING_APP_DISPLAY_LIMIT_KEY = "ranking_app_display_limit"
DEFAULT_APP_DISPLAY_LIMIT = 20
MIN_APP_DISPLAY_LIMIT = 1
MAX_APP_DISPLAY_LIMIT = 100
SNAPSHOT_TTL_SECONDS = 60
DECIMAL_2 = Decimal("0.01")


def normalize_board(board: str) -> str:
    value = (board or "").strip().lower()
    if value not in VALID_BOARDS:
        raise ValueError("board 仅支持 charm/wealth/invite")
    return value


def normalize_period(period: str) -> str:
    value = (period or "").strip().lower()
    if value not in VALID_PERIODS:
        raise ValueError("period 仅支持 day/week/month")
    return value


def score_unit_for_board(board: str) -> str:
    if board == BOARD_WEALTH:
        return "金币"
    if board == BOARD_INVITE:
        return "人"
    return "钻石"


def get_period_window(period: str, *, now: datetime | None = None) -> tuple[datetime, datetime]:
    value = normalize_period(period)
    current = now or now_local_naive()
    today = current.replace(hour=0, minute=0, second=0, microsecond=0)
    if value == PERIOD_DAY:
        return today, today + timedelta(days=1)
    if value == PERIOD_WEEK:
        start = today - timedelta(days=today.weekday())
        return start, start + timedelta(days=7)
    start = today.replace(day=1)
    if start.month == 12:
        end = start.replace(year=start.year + 1, month=1)
    else:
        end = start.replace(month=start.month + 1)
    return start, end


def clamp_app_display_limit(raw_value: object) -> int:
    try:
        value = int(str(raw_value).strip())
    except (TypeError, ValueError):
        return DEFAULT_APP_DISPLAY_LIMIT
    if value < MIN_APP_DISPLAY_LIMIT or value > MAX_APP_DISPLAY_LIMIT:
        return DEFAULT_APP_DISPLAY_LIMIT
    return value


async def get_app_display_limit() -> int:
    raw = await SystemConfig.get_value(
        RANKING_APP_DISPLAY_LIMIT_KEY,
        str(DEFAULT_APP_DISPLAY_LIMIT),
    )
    return clamp_app_display_limit(raw)


async def set_app_display_limit(limit: int) -> int:
    value = clamp_app_display_limit(limit)
    row = await SystemConfig.filter(cfg_key=RANKING_APP_DISPLAY_LIMIT_KEY).first()
    if row:
        row.cfg_value = str(value)
        row.description = "App排行榜展示数量"
        await row.save(update_fields=["cfg_value", "description"])
    else:
        await SystemConfig.create(
            cfg_key=RANKING_APP_DISPLAY_LIMIT_KEY,
            cfg_value=str(value),
            description="App排行榜展示数量",
        )
    try:
        redis = await get_redis()
        await redis.delete(SYSTEM_CONFIG_CACHE_KEY)
    except Exception:  # noqa: BLE001
        pass
    return value


def format_score_value(value: Decimal | int | float | str | None) -> str:
    amount = quantize_decimal_2(value)
    if amount == amount.to_integral_value():
        return str(int(amount))
    return f"{amount.normalize():f}"


def _placeholder(conn) -> str:
    return "%s" if "mysql" in conn.__class__.__module__.lower() else "?"


def _extract_rows(query_result) -> list:
    if isinstance(query_result, tuple):
        if len(query_result) >= 2 and isinstance(query_result[1], (list, tuple)):
            return list(query_result[1])
        if len(query_result) == 1 and isinstance(query_result[0], (list, tuple)):
            return list(query_result[0])
        return []
    rows_attr = getattr(query_result, "rows", None)
    if rows_attr is not None:
        return list(rows_attr)
    if isinstance(query_result, list):
        return query_result
    return []


def _row_get(row, key: str, index: int):
    if isinstance(row, dict):
        return row.get(key)
    return row[index]


def _score(value: Any) -> Decimal:
    return quantize_decimal_2(value)


async def aggregate_board_scores(
    board: str,
    period_start: datetime,
    period_end: datetime,
) -> list[dict[str, Any]]:
    value = normalize_board(board)
    if value == BOARD_INVITE:
        return []

    conn = AppUser._meta.db
    if conn is None:
        return []
    ph = _placeholder(conn)
    params: list[Any] = []

    if value == BOARD_CHARM:
        union_parts = [
            (
                f"SELECT income_certified_user_id AS user_id, COALESCE(certified_user_income_diamonds, 0) AS amount "
                f"FROM call_record WHERE created_at >= {ph} AND created_at < {ph} "
                f"AND income_certified_user_id IS NOT NULL AND COALESCE(certified_user_income_diamonds, 0) > 0"
            ),
            (
                f"SELECT receiver_id AS user_id, COALESCE(certified_user_income_diamonds, 0) AS amount "
                f"FROM gift_record WHERE created_at >= {ph} AND created_at < {ph} "
                f"AND COALESCE(certified_user_income_diamonds, 0) > 0"
            ),
            (
                f"SELECT receiver_id AS user_id, COALESCE(certified_user_income_diamonds, 0) AS amount "
                f"FROM im_text_message_charge_record WHERE created_at >= {ph} AND created_at < {ph} "
                f"AND status = 'charged' AND COALESCE(certified_user_income_diamonds, 0) > 0"
            ),
        ]
        params.extend([period_start, period_end] * 3)
    else:
        union_parts = [
            (
                f"SELECT COALESCE(payer_user_id, caller_id) AS user_id, COALESCE(total_fee, 0) AS amount "
                f"FROM call_record WHERE created_at >= {ph} AND created_at < {ph} "
                f"AND COALESCE(payer_user_id, caller_id) IS NOT NULL AND COALESCE(total_fee, 0) > 0"
            ),
            (
                f"SELECT sender_id AS user_id, COALESCE(total_price, 0) AS amount "
                f"FROM gift_record WHERE created_at >= {ph} AND created_at < {ph} "
                f"AND COALESCE(total_price, 0) > 0"
            ),
            (
                f"SELECT sender_id AS user_id, COALESCE(price, 0) AS amount "
                f"FROM im_text_message_charge_record WHERE created_at >= {ph} AND created_at < {ph} "
                f"AND status = 'charged' AND COALESCE(price, 0) > 0"
            ),
        ]
        params.extend([period_start, period_end] * 3)

    union_sql = " UNION ALL ".join(union_parts)
    sql = f"""
        SELECT src.user_id AS user_id, SUM(src.amount) AS score
        FROM ({union_sql}) AS src
        INNER JOIN app_user u ON u.id = src.user_id
        WHERE u.status = 'normal'
        GROUP BY src.user_id
        HAVING SUM(src.amount) > 0
        ORDER BY score DESC, src.user_id ASC
    """
    result = await conn.execute_query(sql, params)
    rows = _extract_rows(result)
    ranked: list[dict[str, Any]] = []
    for index, row in enumerate(rows, start=1):
        ranked.append(
            {
                "rank": index,
                "user_id": int(_row_get(row, "user_id", 0)),
                "score": _score(_row_get(row, "score", 1)),
            }
        )
    return ranked


async def refresh_ranking_snapshot(board: str, period: str, *, force: bool = False) -> dict[str, Any]:
    board_value = normalize_board(board)
    period_value = normalize_period(period)
    period_start, period_end = get_period_window(period_value)
    lock_key = f"ranking:refresh:{board_value}:{period_value}:{period_start.isoformat()}"
    lock_acquired = False
    redis_available = False
    redis = None
    try:
        redis = await get_redis()
        redis_available = True
        lock_acquired = bool(await redis.set(lock_key, "1", nx=True, ex=30))
    except Exception:  # noqa: BLE001
        lock_acquired = True

    existing = await _latest_snapshot_meta(board_value, period_value, period_start)
    if not redis_available and existing:
        return _snapshot_meta(existing, period_start, period_end)
    if not force and existing and not _is_snapshot_stale(existing.computed_at):
        return _snapshot_meta(existing, period_start, period_end)
    if not lock_acquired and existing:
        return _snapshot_meta(existing, period_start, period_end)
    if not lock_acquired:
        waited = await wait_for_existing_snapshot(board_value, period_value, period_start, period_end)
        if waited:
            return waited

    computed_at = now_local_naive()
    scores = await aggregate_board_scores(board_value, period_start, period_end)
    async with in_transaction() as conn:
        await RankingSnapshot.filter(
            board=board_value,
            period=period_value,
            period_start=period_start,
        ).using_db(conn).delete()
        snapshots = [
            RankingSnapshot(
                board=board_value,
                period=period_value,
                period_start=period_start,
                period_end=period_end,
                user_id=item["user_id"],
                rank=item["rank"],
                score=item["score"],
                computed_at=computed_at,
                source_summary={},
            )
            for item in scores
        ]
        if snapshots:
            await RankingSnapshot.bulk_create(snapshots, using_db=conn)

    if lock_acquired and redis is not None:
        try:
            await redis.delete(lock_key)
        except Exception:  # noqa: BLE001
            pass
    return {
        "board": board_value,
        "period": period_value,
        "period_start": period_start,
        "period_end": period_end,
        "computed_at": computed_at,
        "score_unit": score_unit_for_board(board_value),
    }


def _is_snapshot_stale(computed_at: datetime | None) -> bool:
    if computed_at is None:
        return True
    checked_at = to_local_naive_for_db(computed_at)
    return (now_local_naive() - checked_at).total_seconds() >= SNAPSHOT_TTL_SECONDS


async def _latest_snapshot_meta(board: str, period: str, period_start: datetime) -> RankingSnapshot | None:
    return (
        await RankingSnapshot.filter(board=board, period=period, period_start=period_start)
        .order_by("-computed_at", "rank")
        .first()
    )


def _snapshot_meta(row: RankingSnapshot, period_start: datetime, period_end: datetime) -> dict[str, Any]:
    return {
        "board": row.board,
        "period": row.period,
        "period_start": period_start,
        "period_end": period_end,
        "computed_at": row.computed_at,
        "score_unit": score_unit_for_board(row.board),
    }


async def wait_for_existing_snapshot(
    board: str,
    period: str,
    period_start: datetime,
    period_end: datetime,
    *,
    attempts: int = 5,
    delay_seconds: float = 0.2,
) -> dict[str, Any] | None:
    for _ in range(max(1, attempts)):
        await asyncio.sleep(delay_seconds)
        existing = await _latest_snapshot_meta(board, period, period_start)
        if existing:
            return _snapshot_meta(existing, period_start, period_end)
    return None


async def ensure_current_snapshot(board: str, period: str, *, force: bool = False) -> dict[str, Any]:
    board_value = normalize_board(board)
    period_value = normalize_period(period)
    period_start, period_end = get_period_window(period_value)
    existing = await _latest_snapshot_meta(board_value, period_value, period_start)
    if force or not existing or _is_snapshot_stale(existing.computed_at):
        return await refresh_ranking_snapshot(board_value, period_value, force=force)
    return _snapshot_meta(existing, period_start, period_end)


async def list_snapshot_rows(
    board: str,
    period: str,
    *,
    page: int,
    page_size: int,
    user_id: int | None = None,
) -> tuple[list[dict[str, Any]], int, dict[str, Any]]:
    meta = await ensure_current_snapshot(board, period)
    q = RankingSnapshot.filter(
        board=meta["board"],
        period=meta["period"],
        period_start=meta["period_start"],
    )
    if user_id:
        q = q.filter(user_id=user_id)
    total = await q.count()
    snapshots = await q.order_by("rank").offset((page - 1) * page_size).limit(page_size)
    rows = await enrich_snapshot_rows(snapshots)
    return rows, total, meta


async def enrich_snapshot_rows(snapshots: list[RankingSnapshot]) -> list[dict[str, Any]]:
    if not snapshots:
        return []
    user_ids = [int(item.user_id) for item in snapshots]
    users = await AppUser.filter(id__in=user_ids).all()
    user_map = {int(user.id): user for user in users}
    rows: list[dict[str, Any]] = []
    for item in snapshots:
        user = user_map.get(int(item.user_id))
        if not user:
            continue
        rows.append(
            {
                "rank": int(item.rank),
                "user_id": int(item.user_id),
                "nickname": (user.nickname or "").strip() or (user.phone or "").strip() or f"用户{user.id}",
                "avatar": to_relative_media_url(user.avatar),
                "is_certified_user": bool(user.is_certified_user),
                **vip_payload(user),
                "ranking_invisible_enabled": bool(user.ranking_invisible_enabled),
                "board": item.board,
                "period": item.period,
                "score": _score(item.score),
                "period_start": item.period_start,
                "period_end": item.period_end,
                "computed_at": item.computed_at,
                "source_summary": item.source_summary or {},
            }
        )
    return rows


def build_app_ranking_rows(rows: list[dict[str, Any]], *, board: str) -> list[dict[str, Any]]:
    if not rows:
        return []
    board_value = normalize_board(board)
    unit = score_unit_for_board(board_value)
    top_score = _score(rows[0].get("score"))
    out: list[dict[str, Any]] = []
    for row in rows:
        gap = max(Decimal("0"), top_score - _score(row.get("score")))
        is_anonymous = bool(row.get("ranking_invisible_enabled"))
        out.append(
            {
                "rank": int(row.get("rank") or 0),
                "user_id": None if is_anonymous else int(row.get("user_id") or 0),
                "nickname": "神秘人" if is_anonymous else str(row.get("nickname") or ""),
                "avatar": "" if is_anonymous else str(row.get("avatar") or ""),
                "is_vip": False if is_anonymous else bool(row.get("is_vip")),
                "vip_expires_at": None if is_anonymous else row.get("vip_expires_at"),
                "is_anonymous": is_anonymous,
                "score_gap_from_top": decimal_to_float_2(gap),
                "score_gap_text": f"距榜首 {format_score_value(gap)} {unit}",
            }
        )
    return out


def build_admin_ranking_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for row in rows:
        score = _score(row.get("score"))
        unit = score_unit_for_board(str(row.get("board") or BOARD_CHARM))
        out.append(
            {
                **row,
                "score": decimal_to_float_2(score),
                "score_text": f"{format_score_value(score)} {unit}",
            }
        )
    return out


async def list_app_ranking(board: str, period: str) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    limit = await get_app_display_limit()
    rows, _total, meta = await list_snapshot_rows(board, period, page=1, page_size=limit)
    customer_service_user_id = await get_customer_service_user_id()
    if customer_service_user_id:
        visible_rows: list[dict[str, Any]] = []
        for row in rows:
            if customer_service_user_id and int(row.get("user_id") or 0) == customer_service_user_id:
                continue
            visible_rows.append(row)
        rows = visible_rows
    app_rows = build_app_ranking_rows(rows, board=meta["board"])
    meta["app_display_limit"] = limit
    return app_rows, meta


async def list_admin_ranking(
    board: str,
    period: str,
    *,
    page: int,
    page_size: int,
    user_id: int | None = None,
) -> tuple[list[dict[str, Any]], int, dict[str, Any]]:
    rows, total, meta = await list_snapshot_rows(
        board,
        period,
        page=page,
        page_size=page_size,
        user_id=user_id,
    )
    return build_admin_ranking_rows(rows), total, meta


async def ensure_default_config() -> None:
    exists = await SystemConfig.filter(cfg_key=RANKING_APP_DISPLAY_LIMIT_KEY).exists()
    if not exists:
        await SystemConfig.create(
            cfg_key=RANKING_APP_DISPLAY_LIMIT_KEY,
            cfg_value=str(DEFAULT_APP_DISPLAY_LIMIT),
            description="App排行榜展示数量",
        )
