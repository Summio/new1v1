import asyncio
import random
from datetime import timedelta
from dataclasses import dataclass

from app.log import logger
from app.models import AppUser, CallRecord
from app.models.system_config import SystemConfig
from app.core.time_utils import now_local_naive, to_utc_aware
from app.services.call_trace_service import CallTraceService
from tortoise.expressions import F
from tortoise.transactions import in_transaction

FREE_SECONDS_BEFORE_BILLING = 10
DEFAULT_POLL_SECONDS = 5
DEFAULT_RING_TIMEOUT_SECONDS = 30
DEFAULT_RENEW_GRACE_SECONDS = 5
MAX_RENEW_GRACE_SECONDS = 5
MAX_WATCHDOG_SECONDS = 600
MIN_WATCHDOG_SECONDS = 1
MAX_WATCHDOG_BATCH_SIZE = 100


@dataclass(frozen=True)
class WatchdogConfig:
    poll_seconds: int
    ring_timeout_seconds: int
    renew_grace_seconds: int
    free_seconds_before_billing: int


def _safe_parse_int(raw: str | None, default: int) -> int:
    if raw is None:
        return default
    try:
        return int(str(raw).strip())
    except (TypeError, ValueError):
        return default


def _clamp_seconds(value: int) -> int:
    if value < MIN_WATCHDOG_SECONDS:
        return MIN_WATCHDOG_SECONDS
    if value > MAX_WATCHDOG_SECONDS:
        return MAX_WATCHDOG_SECONDS
    return value


def _clamp_renew_grace_seconds(value: int) -> int:
    if value < 0:
        return 0
    if value > MAX_RENEW_GRACE_SECONDS:
        return MAX_RENEW_GRACE_SECONDS
    return value


async def _load_watchdog_config() -> WatchdogConfig:
    poll_raw = await SystemConfig.get_value(
        "call_watchdog_poll_seconds",
        str(DEFAULT_POLL_SECONDS),
    )
    ring_raw = await SystemConfig.get_value(
        "call_watchdog_ring_timeout_seconds",
        str(DEFAULT_RING_TIMEOUT_SECONDS),
    )
    grace_raw = await SystemConfig.get_value(
        "call_watchdog_renew_grace_seconds",
        str(DEFAULT_RENEW_GRACE_SECONDS),
    )
    free_raw = await SystemConfig.get_value(
        "call_billing_free_seconds",
        str(FREE_SECONDS_BEFORE_BILLING),
    )
    return WatchdogConfig(
        poll_seconds=_clamp_seconds(_safe_parse_int(poll_raw, DEFAULT_POLL_SECONDS)),
        ring_timeout_seconds=_clamp_seconds(
            _safe_parse_int(ring_raw, DEFAULT_RING_TIMEOUT_SECONDS)
        ),
        renew_grace_seconds=_clamp_renew_grace_seconds(
            _safe_parse_int(grace_raw, DEFAULT_RENEW_GRACE_SECONDS)
        ),
        free_seconds_before_billing=max(0, _safe_parse_int(free_raw, FREE_SECONDS_BEFORE_BILLING)),
    )


def _calc_due_minutes(duration_seconds: int, free_seconds_before_billing: int) -> int:
    if duration_seconds < free_seconds_before_billing:
        return 0
    return (duration_seconds + 59) // 60


def _next_due_second(deducted_minutes: int, free_seconds_before_billing: int) -> int:
    normalized_deducted = max(0, deducted_minutes)
    if normalized_deducted == 0:
        return free_seconds_before_billing
    return normalized_deducted * 60


def _resolve_billing_free_seconds(raw_snapshot: int | None, default_seconds: int) -> int:
    if raw_snapshot is None:
        return max(0, int(default_seconds))
    return max(0, int(raw_snapshot))


def _resolve_payer_user_id(raw_snapshot: int | None) -> int | None:
    if raw_snapshot is None:
        return None
    return int(raw_snapshot)


def _build_coins_decrement_expr(amount: int):
    return F("coins") - int(amount)


async def _try_become_watchdog_leader() -> bool:
    try:
        from app.websocket.manager import try_acquire_watchdog_leader

        return await try_acquire_watchdog_leader()
    except Exception:
        return False


async def _refresh_watchdog_leader() -> bool:
    try:
        from app.websocket.manager import refresh_watchdog_leader

        return await refresh_watchdog_leader()
    except Exception:
        return False


async def _close_timeout_pending(config: WatchdogConfig) -> None:
    timeout_before = now_local_naive() - timedelta(
        seconds=config.ring_timeout_seconds
    )
    call_ids = await CallRecord.filter(
        status="pending",
        created_at__lt=timeout_before,
    ).limit(MAX_WATCHDOG_BATCH_SIZE).values_list("id", flat=True)
    if not call_ids:
        return

    trace_service = CallTraceService()
    updated_call_ids: list[int] = []
    # P-1: 单事务批量更新，避免逐条开事务的开销
    async with in_transaction() as conn:
        for call_id in call_ids:
            updated = await CallRecord.filter(
                id=call_id,
                status="pending",
            ).using_db(conn).select_for_update().update(
                status="ended",
                end_reason="timeout",
                ended_at=now_local_naive(),
            )
            if updated == 0:
                continue
            updated_call_ids.append(int(call_id))
        # 事务已提交，追踪写入和 WebSocket 推送可安全异步执行
    for call_id in updated_call_ids:
        call_record = await CallRecord.filter(id=call_id).first()
        if call_record:
            if call_record.status != "ended" or call_record.end_reason != "timeout":
                continue
            await trace_service.append(
                call_record=call_record,
                phase="timeout",
                actor_user_id=int(call_record.caller_id),
                reason="timeout",
            )
            # 推送 WebSocket 事件
            asyncio.create_task(_ws_push_call_timeout(call_record))


async def _close_stale_ongoing(config: WatchdogConfig) -> None:
    """
    P-6 修复：分批处理避免单事务持有过多行锁；
    批量预加载 anchor 状态，减少 N 次 DB 查询。
    """
    ids = (
        await CallRecord.filter(status="ongoing")
        .limit(MAX_WATCHDOG_BATCH_SIZE)
        .values_list("id", flat=True)
    )
    if not ids:
        return

    trace_service = CallTraceService()
    ended_records: list[CallRecord] = []

    # 预加载 anchor 状态（跨批次复用，避免重复查询）
    from app.models import Anchor
    raw_records = (
        await CallRecord.filter(id__in=list(ids), status="ongoing")
        .order_by("id")
        .values("id", "caller_id", "callee_id", "connected_at",
                 "deducted_minutes", "deducted_amount", "call_price",
                 "billing_free_seconds", "payer_user_id")
    )
    all_user_ids = set()
    for r in raw_records:
        all_user_ids.add(int(r["caller_id"]))
        all_user_ids.add(int(r["callee_id"]))
    anchor_user_ids = set(
        await Anchor.filter(
            app_user_id__in=list(all_user_ids),
            apply_status="approved",
        ).values_list("app_user_id", flat=True)
    )

    # P-6 修复：分批处理，每批 20 条记录，避免单事务持有过多行锁
    BATCH_SIZE = 20
    charged_records: list[tuple[CallRecord, int]] = []  # (call_record, payer_id)
    for batch_start in range(0, len(raw_records), BATCH_SIZE):
        batch = raw_records[batch_start : batch_start + BATCH_SIZE]
        batch_ended, batch_charged = await _process_stale_batch(config, batch, anchor_user_ids)
        ended_records.extend(batch_ended)
        charged_records.extend(batch_charged)

    # 追踪写入移出事务
    for call_record in ended_records:
        await trace_service.append(
            call_record=call_record,
            phase="balance_empty",
            actor_user_id=int(call_record.caller_id),
            reason="balance_empty",
        )
        # 推送 WebSocket 事件
        asyncio.create_task(_ws_push_call_balance_empty(call_record))

    # 推送成功扣费的余额更新（fire-and-forget）
    for call_record, payer_id in charged_records:
        asyncio.create_task(_ws_push_balance_updated_for_charge(payer_id))


async def _process_stale_batch(
    config: WatchdogConfig,
    batch: list[dict],
    anchor_user_ids: set[int],
) -> tuple[list[CallRecord], list[tuple[CallRecord, int]]]:
    """处理一批通话记录，单独事务，返回(结束的记录列表, 成功扣费的记录列表)"""
    ended_records: list[CallRecord] = []
    charged_records: list[tuple[CallRecord, int]] = []
    async with in_transaction() as conn:
        for r in batch:
            call_record = (
                await CallRecord.filter(id=r["id"], status="ongoing")
                .using_db(conn)
                .select_for_update()
                .first()
            )
            if not call_record:
                continue

            if not call_record.connected_at:
                continue

            duration = int(
                max(
                    0,
                    (
                        to_utc_aware(now_local_naive())
                        - to_utc_aware(call_record.connected_at)
                    ).total_seconds(),
                )
            )
            free_seconds_before_billing = _resolve_billing_free_seconds(
                getattr(call_record, "billing_free_seconds", None),
                config.free_seconds_before_billing,
            )
            deducted_minutes = int(call_record.deducted_minutes or 0)
            due_minutes = _calc_due_minutes(duration, free_seconds_before_billing)
            next_due = _next_due_second(deducted_minutes, free_seconds_before_billing)
            overdue_seconds = duration - next_due

            if due_minutes <= deducted_minutes:
                continue
            if overdue_seconds < config.renew_grace_seconds:
                continue

            payer_id = _resolve_payer_user_id(getattr(call_record, "payer_user_id", None))
            if payer_id is None:
                caller_id = int(r["caller_id"])
                callee_id = int(r["callee_id"])
                caller_is_anchor = caller_id in anchor_user_ids
                callee_is_anchor = callee_id in anchor_user_ids

                if caller_is_anchor and not callee_is_anchor:
                    payer_id = callee_id
                elif callee_is_anchor and not caller_is_anchor:
                    payer_id = caller_id
                elif not caller_is_anchor and not callee_is_anchor:
                    payer_id = caller_id
                else:
                    call_record.last_renew_at = now_local_naive()
                    await call_record.save(using_db=conn)
                    continue

            to_charge_minutes = due_minutes - deducted_minutes
            charge_amount = to_charge_minutes * int(call_record.call_price or 0)

            payer = (
                await AppUser.filter(id=payer_id)
                .using_db(conn)
                .select_for_update()
                .first()
            )
            if not payer or payer.coins < charge_amount:
                call_record.status = "ended"
                call_record.end_reason = "balance_empty"
                call_record.duration = duration
                call_record.deducted_minutes = deducted_minutes
                call_record.total_fee = int(call_record.deducted_amount or 0)
                call_record.ended_at = now_local_naive()
                await call_record.save(using_db=conn)
                logger.warning(
                    "watchdog closed call_id={} caller_id={} callee_id={} (balance insufficient) duration={}s",
                    r["id"],
                    r["caller_id"],
                    r["callee_id"],
                    duration,
                )
                ended_records.append(call_record)
                continue

            updated = await AppUser.filter(
                id=payer_id, coins__gte=charge_amount,
            ).using_db(conn).update(coins=_build_coins_decrement_expr(charge_amount))
            if updated == 0:
                call_record.status = "ended"
                call_record.end_reason = "balance_empty"
                call_record.duration = duration
                call_record.deducted_minutes = deducted_minutes
                call_record.total_fee = int(call_record.deducted_amount or 0)
                call_record.ended_at = now_local_naive()
                await call_record.save(using_db=conn)
                logger.warning(
                    "watchdog closed call_id={} caller_id={} callee_id={} (conditional update failed) duration={}s",
                    r["id"],
                    r["caller_id"],
                    r["callee_id"],
                    duration,
                )
                ended_records.append(call_record)
                continue

            call_record.deducted_minutes = due_minutes
            call_record.deducted_amount = int(call_record.deducted_amount or 0) + charge_amount
            call_record.last_renew_at = now_local_naive()
            await call_record.save(using_db=conn)
            logger.info(
                "watchdog charged call_id={} payer={} minutes={} amount={}",
                r["id"],
                payer_id,
                to_charge_minutes,
                charge_amount,
            )
            # 记录成功扣费的记录，用于推送余额更新
            charged_records.append((call_record, payer_id))

    return ended_records, charged_records


async def _ws_push_call_timeout(call_record: CallRecord) -> None:
    """推送通话超时事件到 WebSocket（fire-and-forget）。"""
    try:
        from app.websocket import events as ws_events
        await ws_events.push_call_timeout(
            caller_id=int(call_record.caller_id),
            callee_id=int(call_record.callee_id),
            call_id=int(call_record.id),
        )
    except Exception as e:  # noqa: BLE001
        logger.warning("ws push call_timeout failed: {}", str(e))


async def _ws_push_call_balance_empty(call_record: CallRecord) -> None:
    """推送余额不足关闭事件到 WebSocket（fire-and-forget）。"""
    try:
        from app.websocket import events as ws_events
        await ws_events.push_call_balance_empty(
            caller_id=int(call_record.caller_id),
            callee_id=int(call_record.callee_id),
            call_id=int(call_record.id),
        )
    except Exception as e:  # noqa: BLE001
        logger.warning("ws push call_balance_empty failed: {}", str(e))


async def _ws_push_balance_updated_for_charge(payer_id: int) -> None:
    """Watchdog 扣费成功后推送余额更新给付费方（fire-and-forget）。"""
    try:
        from app.websocket import events as ws_events
        from app.models import AppUser

        payer = await AppUser.filter(id=payer_id).first()
        if payer:
            await ws_events.push_balance_update(
                user_id=payer_id,
                coins=payer.coins,
                diamonds=payer.diamonds,
            )
    except Exception as e:  # noqa: BLE001
        logger.warning("ws push balance_updated for charge failed: {}", str(e))


async def run_call_watchdog(stop_event: asyncio.Event) -> None:
    logger.info("call watchdog started")

    # H2 修复：连续续期失败计数，用于 leader 丢失告警
    _leader_refresh_fail_count = 0
    _MAX_REFRESH_FAIL_BEFORE_ALERT = 3

    try:
        # 多 worker 部署下，只有 leader worker 执行 watchdog 逻辑
        # leader 通过 Redis SET NX EX 保证唯一性，TTL 60s 作为兜底
        is_leader = await _try_become_watchdog_leader()
        if is_leader:
            logger.info("call watchdog: acquired leader")
        else:
            logger.info("call watchdog: follower mode (no leader)")

        while not stop_event.is_set():
            try:
                config = await _load_watchdog_config()
            except Exception as e:  # noqa: BLE001
                logger.exception("watchdog config load failed: {}", str(e))
                await asyncio.sleep(5)
                continue

            try:
                if is_leader:
                    # Leader 执行 watchdog 逻辑
                    await _close_timeout_pending(config)
                    await _close_stale_ongoing(config)
                    # 续期 leader 身份
                    if not await _refresh_watchdog_leader():
                        # leader 身份丢失，重新竞争
                        is_leader = await _try_become_watchdog_leader()
                        _leader_refresh_fail_count += 1
                        if is_leader:
                            _leader_refresh_fail_count = 0
                            logger.info("call watchdog: re-acquired leader")
                        else:
                            # H2 修复：连续 N 次续期失败后记录 WARNING 供监控告警
                            if _leader_refresh_fail_count >= _MAX_REFRESH_FAIL_BEFORE_ALERT:
                                logger.warning(
                                    "call watchdog: leader renewal failed {} times consecutively",
                                    _leader_refresh_fail_count,
                                )
                            logger.info("call watchdog: lost leader, switching to follower")
                    else:
                        _leader_refresh_fail_count = 0
                else:
                    # Follower 尝试竞争 leader
                    if await _try_become_watchdog_leader():
                        is_leader = True
                        _leader_refresh_fail_count = 0
                        logger.info("call watchdog: acquired leader")
                    else:
                        # W-5 修复：随机退避避免惊群效应
                        await asyncio.sleep(random.uniform(1, 5))

            except Exception as e:  # noqa: BLE001
                logger.exception("call watchdog loop error: {}", str(e))

            poll_seconds = config.poll_seconds if is_leader else 5
            try:
                await asyncio.wait_for(stop_event.wait(), timeout=poll_seconds)
            except asyncio.TimeoutError:
                pass
    finally:
        logger.info("call watchdog stopped")
