import asyncio
import random
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from tortoise.expressions import F
from tortoise.transactions import in_transaction

from app.core.call_presence import (
    clear_left_candidate,
    get_snapshot,
    mark_left_candidate,
)
from app.core.time_utils import now_local_naive, to_local_naive_for_db, to_utc_aware
from app.log import logger
from app.models import AppUser, CallRecord
from app.models.system_config import SystemConfig
from app.services.balance_event_service import publish_balance_changed
from app.services.call_income_service import settle_call_certified_user_income_once
from app.services.call_trace_service import CallTraceService
from app.services.service_fee_service import (
    apply_call_service_fee_final_adjustment,
    calc_call_income_service_fee_for_minutes,
    calc_call_service_fee_for_minutes,
    calc_incremental_chargeable_minutes,
    quantize_decimal_2,
    resolve_call_service_fee_payer_status,
)
from app.utils.parse import clamp_int, safe_parse_int

FREE_SECONDS_BEFORE_BILLING = 10
DEFAULT_POLL_SECONDS = 5
DEFAULT_RING_TIMEOUT_SECONDS = 30
DEFAULT_RENEW_GRACE_SECONDS = 5
MAX_RENEW_GRACE_SECONDS = 5
MAX_WATCHDOG_SECONDS = 600
MIN_WATCHDOG_SECONDS = 1
MAX_WATCHDOG_BATCH_SIZE = 100
DEFAULT_PRESENCE_OFFLINE_DETECT_SECONDS = 3
DEFAULT_PRESENCE_SETTLE_GRACE_SECONDS = 5
MAX_PRESENCE_SETTLE_GRACE_SECONDS = 30
DEFAULT_CERTIFIED_USER_SHARE_BPS = 5000
MAX_CERTIFIED_USER_SHARE_BPS = 10000


@dataclass(frozen=True)
class WatchdogConfig:
    poll_seconds: int
    ring_timeout_seconds: int
    renew_grace_seconds: int
    free_seconds_before_billing: int
    presence_offline_detect_seconds: int = DEFAULT_PRESENCE_OFFLINE_DETECT_SECONDS
    presence_settle_grace_seconds: int = DEFAULT_PRESENCE_SETTLE_GRACE_SECONDS


@dataclass(frozen=True)
class ForceExitDecision:
    should_end: bool
    end_reason: str | None
    effective_ended_at_ms: int | None
    force_exit_user_id: int | None
    mark_candidate_roles: tuple[str, ...] = ()
    clear_candidate_roles: tuple[str, ...] = ()


@dataclass(frozen=True)
class WatchdogBillingResult:
    ended_records: list[CallRecord]
    charged_payer_ids: list[int]
    certified_user_balance_pushes: list[int]


def _clamp_seconds(value: int) -> int:
    return clamp_int(value, MIN_WATCHDOG_SECONDS, MAX_WATCHDOG_SECONDS)


def _clamp_renew_grace_seconds(value: int) -> int:
    return clamp_int(value, 0, MAX_RENEW_GRACE_SECONDS)


def _clamp_presence_settle_grace_seconds(value: int) -> int:
    return clamp_int(value, 0, MAX_PRESENCE_SETTLE_GRACE_SECONDS)


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
    offline_detect_raw = await SystemConfig.get_value(
        "call_presence_offline_detect_seconds",
        str(DEFAULT_PRESENCE_OFFLINE_DETECT_SECONDS),
    )
    settle_grace_raw = await SystemConfig.get_value(
        "call_presence_settle_grace_seconds",
        str(DEFAULT_PRESENCE_SETTLE_GRACE_SECONDS),
    )
    return WatchdogConfig(
        poll_seconds=_clamp_seconds(safe_parse_int(poll_raw, DEFAULT_POLL_SECONDS)),
        ring_timeout_seconds=_clamp_seconds(safe_parse_int(ring_raw, DEFAULT_RING_TIMEOUT_SECONDS)),
        renew_grace_seconds=_clamp_renew_grace_seconds(safe_parse_int(grace_raw, DEFAULT_RENEW_GRACE_SECONDS)),
        free_seconds_before_billing=max(0, safe_parse_int(free_raw, FREE_SECONDS_BEFORE_BILLING)),
        presence_offline_detect_seconds=_clamp_seconds(
            safe_parse_int(
                offline_detect_raw,
                DEFAULT_PRESENCE_OFFLINE_DETECT_SECONDS,
            )
        ),
        presence_settle_grace_seconds=_clamp_presence_settle_grace_seconds(
            safe_parse_int(
                settle_grace_raw,
                DEFAULT_PRESENCE_SETTLE_GRACE_SECONDS,
            )
        ),
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


async def _apply_incremental_call_service_fee(
    *,
    call_record: CallRecord,
    payer: AppUser | None,
    conn,
) -> bool:
    legacy_rate_bps = int(getattr(call_record, "service_fee_rate_bps", 0) or 0)
    payer_rate_bps = int(getattr(call_record, "service_fee_payer_rate_bps", legacy_rate_bps) or legacy_rate_bps)
    income_rate_bps = int(getattr(call_record, "service_fee_income_rate_bps", legacy_rate_bps) or legacy_rate_bps)
    threshold_minutes = int(getattr(call_record, "service_fee_threshold_minutes", 0) or 0)
    if payer_rate_bps <= 0 and income_rate_bps <= 0:
        return False

    deducted_minutes = int(getattr(call_record, "deducted_minutes", 0) or 0)
    processed_minutes = int(getattr(call_record, "service_fee_processed_chargeable_minutes", 0) or 0)
    incremental_minutes = calc_incremental_chargeable_minutes(
        previous_processed=processed_minutes,
        deducted_minutes=deducted_minutes,
        threshold_minutes=threshold_minutes,
    )
    if incremental_minutes <= 0:
        return False

    payer_fee_per_minute = calc_call_service_fee_for_minutes(
        call_price=int(getattr(call_record, "call_price", 0) or 0),
        chargeable_minutes=1,
        rate_bps=payer_rate_bps,
    )
    income_fee_per_minute = calc_call_income_service_fee_for_minutes(
        call_price=int(getattr(call_record, "call_price", 0) or 0),
        certified_user_share_bps=int(getattr(call_record, "certified_user_share_bps", 0) or 0),
        chargeable_minutes=1,
        rate_bps=income_rate_bps,
    )

    payer_expected = quantize_decimal_2(getattr(call_record, "service_fee_payer_expected_coins", 0))
    payer_actual = quantize_decimal_2(getattr(call_record, "service_fee_payer_actual_coins", 0))
    income_expected = quantize_decimal_2(getattr(call_record, "service_fee_income_expected_diamonds", 0))
    payer_balance_changed = False

    for _ in range(incremental_minutes):
        payer_expected = quantize_decimal_2(payer_expected + payer_fee_per_minute)
        income_expected = quantize_decimal_2(income_expected + income_fee_per_minute)
        if payer and payer_fee_per_minute > 0 and quantize_decimal_2(payer.coins) >= payer_fee_per_minute:
            payer.coins = quantize_decimal_2(quantize_decimal_2(payer.coins) - payer_fee_per_minute)
            payer_actual = quantize_decimal_2(payer_actual + payer_fee_per_minute)
            payer_balance_changed = True

    call_record.service_fee_processed_chargeable_minutes = processed_minutes + incremental_minutes
    call_record.service_fee_payer_expected_coins = payer_expected
    call_record.service_fee_payer_actual_coins = payer_actual
    call_record.service_fee_payer_status = resolve_call_service_fee_payer_status(
        expected_amount=payer_expected,
        actual_amount=payer_actual,
    )
    call_record.service_fee_payer_settled_at = now_local_naive() if call_record.service_fee_payer_status else None
    call_record.service_fee_income_expected_diamonds = income_expected
    if payer and payer_balance_changed:
        await payer.save(using_db=conn, update_fields=["coins"])
    return payer_balance_changed


def _resolve_income_certified_user_id(
    *,
    caller_id: int,
    callee_id: int,
    payer_id: int | None,
    certified_user_ids: set[int],
) -> int:
    if payer_id is None or payer_id <= 0:
        return 0
    if caller_id in certified_user_ids and caller_id != payer_id:
        return caller_id
    if callee_id in certified_user_ids and callee_id != payer_id:
        return callee_id
    return 0


def _resolve_income_certified_user_id_for_call(
    *,
    caller_id: int,
    callee_id: int,
    payer_id: int | None,
    certified_user_ids: set[int],
) -> int:
    if payer_id is None or payer_id <= 0:
        return 0
    if caller_id in certified_user_ids and callee_id in certified_user_ids:
        return callee_id if payer_id == caller_id else caller_id
    return _resolve_income_certified_user_id(
        caller_id=caller_id,
        callee_id=callee_id,
        payer_id=payer_id,
        certified_user_ids=certified_user_ids,
    )


def _now_ms() -> int:
    return int(now_local_naive().timestamp() * 1000)


def _ms_to_local_naive(ms: int) -> datetime:
    return to_local_naive_for_db(datetime.fromtimestamp(ms / 1000, timezone.utc))


def _resolve_force_exit_decision(
    *,
    call_id: int,
    connected_at: datetime,
    caller_id: int,
    callee_id: int,
    snapshot: dict[str, int | None],
    now_ms: int,
    offline_detect_seconds: int,
    settle_grace_seconds: int,
) -> ForceExitDecision:
    detect_ms = int(max(0, offline_detect_seconds) * 1000)
    settle_ms = int(max(0, settle_grace_seconds) * 1000)
    connected_ms = int(to_utc_aware(connected_at).timestamp() * 1000)

    mark_roles: list[str] = []
    clear_roles: list[str] = []
    settled_candidates: list[tuple[int, int]] = []  # (effective_ms, user_id)

    def _eval_role(role: str, user_id: int) -> None:
        last_seen = snapshot.get(f"{role}_last_seen_ms")
        left_candidate = snapshot.get(f"{role}_left_candidate_ms")
        effective_last_seen = int(last_seen or connected_ms)
        stale = (now_ms - effective_last_seen) > detect_ms
        if not stale:
            if left_candidate is not None:
                clear_roles.append(role)
            return

        if left_candidate is None:
            mark_roles.append(role)
            return

        if (now_ms - int(left_candidate)) >= settle_ms:
            settled_candidates.append((effective_last_seen, user_id))

    _eval_role("caller", int(caller_id))
    _eval_role("callee", int(callee_id))

    if not settled_candidates:
        return ForceExitDecision(
            should_end=False,
            end_reason=None,
            effective_ended_at_ms=None,
            force_exit_user_id=None,
            mark_candidate_roles=tuple(mark_roles),
            clear_candidate_roles=tuple(clear_roles),
        )

    settled_candidates.sort(key=lambda x: x[0])
    effective_ended_at_ms, force_exit_user_id = settled_candidates[0]
    logger.warning(
        "watchdog force_exit candidate settled: call_id={} force_exit_user_id={} effective_ms={}",
        call_id,
        force_exit_user_id,
        effective_ended_at_ms,
    )
    return ForceExitDecision(
        should_end=True,
        end_reason="force_exit",
        effective_ended_at_ms=effective_ended_at_ms,
        force_exit_user_id=force_exit_user_id,
        mark_candidate_roles=tuple(mark_roles),
        clear_candidate_roles=tuple(clear_roles),
    )


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
    timeout_before = now_local_naive() - timedelta(seconds=config.ring_timeout_seconds)
    call_ids = (
        await CallRecord.filter(
            status="pending",
            created_at__lt=timeout_before,
        )
        .limit(MAX_WATCHDOG_BATCH_SIZE)
        .values_list("id", flat=True)
    )
    if not call_ids:
        return

    trace_service = CallTraceService()
    updated_call_ids: list[int] = []
    # P-1: 单事务批量更新，避免逐条开事务的开销
    async with in_transaction() as conn:
        for call_id in call_ids:
            updated = (
                await CallRecord.filter(
                    id=call_id,
                    status="pending",
                )
                .using_db(conn)
                .select_for_update()
                .update(
                    status="ended",
                    end_reason="timeout",
                    ended_at=now_local_naive(),
                    effective_ended_at=now_local_naive(),
                    end_basis="timeout",
                    force_exit_user_id=None,
                )
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
    批量预加载认证用户状态，减少 N 次 DB 查询。
    """
    ids = await CallRecord.filter(status="ongoing").limit(MAX_WATCHDOG_BATCH_SIZE).values_list("id", flat=True)
    if not ids:
        return

    trace_service = CallTraceService()
    ended_records: list[CallRecord] = []
    certified_user_balance_pushes: list[int] = []

    # 预加载认证用户状态（跨批次复用，避免重复查询）
    raw_records = (
        await CallRecord.filter(id__in=list(ids), status="ongoing")
        .order_by("id")
        .values(
            "id",
            "caller_id",
            "callee_id",
            "connected_at",
            "deducted_minutes",
            "deducted_amount",
            "call_price",
            "billing_free_seconds",
            "payer_user_id",
        )
    )
    all_user_ids = set()
    for r in raw_records:
        all_user_ids.add(int(r["caller_id"]))
        all_user_ids.add(int(r["callee_id"]))
    certified_user_ids = set(
        await AppUser.filter(
            id__in=list(all_user_ids),
            is_certified_user=True,
        ).values_list("id", flat=True)
    )

    # P-6 修复：分批处理，每批 20 条记录，避免单事务持有过多行锁
    BATCH_SIZE = 20
    charged_records: list[tuple[CallRecord, int]] = []  # (call_record, payer_id)
    for batch_start in range(0, len(raw_records), BATCH_SIZE):
        batch = raw_records[batch_start : batch_start + BATCH_SIZE]
        batch_ended, batch_charged, batch_certified_user_pushes = await _process_stale_batch(
            config,
            batch,
            certified_user_ids,
        )
        ended_records.extend(batch_ended)
        charged_records.extend(batch_charged)
        certified_user_balance_pushes.extend(batch_certified_user_pushes)

    # 追踪写入移出事务
    for call_record in ended_records:
        if call_record.end_reason == "force_exit":
            await trace_service.append(
                call_record=call_record,
                phase="force_exit",
                actor_user_id=int(call_record.force_exit_user_id or call_record.caller_id),
                reason="force_exit",
            )
            asyncio.create_task(_ws_push_call_force_exit(call_record))
            continue

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
    for certified_user_id in certified_user_balance_pushes:
        asyncio.create_task(_ws_push_balance_updated_for_charge(certified_user_id))


async def process_ongoing_call_billing_once(call_id: int) -> WatchdogBillingResult:
    config = await _load_watchdog_config()
    raw_records = await CallRecord.filter(id=int(call_id), status="ongoing").values(
        "id",
        "caller_id",
        "callee_id",
        "connected_at",
        "deducted_minutes",
        "deducted_amount",
        "call_price",
        "billing_free_seconds",
        "payer_user_id",
    )
    if not raw_records:
        return WatchdogBillingResult(
            ended_records=[],
            charged_payer_ids=[],
            certified_user_balance_pushes=[],
        )

    all_user_ids: set[int] = set()
    for record in raw_records:
        all_user_ids.add(int(record["caller_id"]))
        all_user_ids.add(int(record["callee_id"]))
    certified_user_ids = set(
        await AppUser.filter(
            id__in=list(all_user_ids),
            is_certified_user=True,
        ).values_list("id", flat=True)
    )

    ended_records, charged_records, certified_user_balance_pushes = await _process_stale_batch(
        config,
        raw_records,
        certified_user_ids,
    )
    return WatchdogBillingResult(
        ended_records=ended_records,
        charged_payer_ids=[payer_id for _, payer_id in charged_records],
        certified_user_balance_pushes=certified_user_balance_pushes,
    )


async def _process_stale_batch(
    config: WatchdogConfig,
    batch: list[dict],
    certified_user_ids: set[int],
) -> tuple[list[CallRecord], list[tuple[CallRecord, int]], list[int]]:
    """处理一批通话记录，单独事务，返回(结束的记录列表, 成功扣费的记录列表)"""
    ended_records: list[CallRecord] = []
    charged_records: list[tuple[CallRecord, int]] = []
    certified_user_balance_pushes: list[int] = []

    def _resolve_payer_id_from_record(raw: dict, call_record_obj: CallRecord) -> int | None:
        payer_id = _resolve_payer_user_id(getattr(call_record_obj, "payer_user_id", None))
        if payer_id is not None:
            return payer_id

        caller_id = int(raw["caller_id"])
        callee_id = int(raw["callee_id"])
        caller_is_certified_user = caller_id in certified_user_ids
        callee_is_certified_user = callee_id in certified_user_ids
        if caller_is_certified_user and not callee_is_certified_user:
            return callee_id
        if callee_is_certified_user and not caller_is_certified_user:
            return caller_id
        if caller_is_certified_user and callee_is_certified_user:
            return caller_id
        return None

    async with in_transaction() as conn:
        for r in batch:
            call_record = (
                await CallRecord.filter(id=r["id"], status="ongoing").using_db(conn).select_for_update().first()
            )
            if not call_record:
                continue

            if not call_record.connected_at:
                continue

            now_ms = _now_ms()
            presence_snapshot = await get_snapshot(call_id=int(call_record.id))
            force_exit_decision = _resolve_force_exit_decision(
                call_id=int(call_record.id),
                connected_at=call_record.connected_at,
                caller_id=int(r["caller_id"]),
                callee_id=int(r["callee_id"]),
                snapshot=presence_snapshot,
                now_ms=now_ms,
                offline_detect_seconds=config.presence_offline_detect_seconds,
                settle_grace_seconds=config.presence_settle_grace_seconds,
            )
            for role in force_exit_decision.clear_candidate_roles:
                await clear_left_candidate(call_id=int(call_record.id), role=role)
            for role in force_exit_decision.mark_candidate_roles:
                await mark_left_candidate(
                    call_id=int(call_record.id),
                    role=role,
                    now_ms=now_ms,
                )

            free_seconds_before_billing = _resolve_billing_free_seconds(
                getattr(call_record, "billing_free_seconds", None),
                config.free_seconds_before_billing,
            )

            if force_exit_decision.should_end and force_exit_decision.effective_ended_at_ms is not None:
                payer_id = _resolve_payer_id_from_record(r, call_record)
                effective_ended_at = _ms_to_local_naive(force_exit_decision.effective_ended_at_ms)
                duration = int(
                    max(
                        0,
                        (to_utc_aware(effective_ended_at) - to_utc_aware(call_record.connected_at)).total_seconds(),
                    )
                )
                due_minutes = _calc_due_minutes(duration, free_seconds_before_billing)
                actual_fee = due_minutes * int(call_record.call_price or 0)
                deducted_amount = int(call_record.deducted_amount or 0)
                charged_amount = deducted_amount

                if actual_fee > deducted_amount and payer_id is not None and payer_id > 0:
                    top_up_amount = actual_fee - deducted_amount
                    await AppUser.filter(id=payer_id).using_db(conn).select_for_update().first()
                    updated = (
                        await AppUser.filter(
                            id=payer_id,
                            coins__gte=top_up_amount,
                        )
                        .using_db(conn)
                        .update(coins=F("coins") - top_up_amount)
                    )
                    if updated > 0:
                        charged_amount += top_up_amount
                        charged_records.append((call_record, payer_id))

                if actual_fee < deducted_amount and payer_id is not None and payer_id > 0:
                    refund_amount = deducted_amount - actual_fee
                    await AppUser.filter(id=payer_id).using_db(conn).select_for_update().first()
                    await AppUser.filter(id=payer_id).using_db(conn).update(coins=F("coins") + refund_amount)
                    charged_amount -= refund_amount
                    charged_records.append((call_record, payer_id))

                call_record.status = "ended"
                call_record.end_reason = "force_exit"
                call_record.duration = duration
                if payer_id is not None and payer_id > 0 and int(call_record.call_price or 0) > 0:
                    call_record.deducted_minutes = charged_amount // int(call_record.call_price or 0)
                else:
                    call_record.deducted_minutes = due_minutes
                call_record.deducted_amount = charged_amount
                call_record.total_fee = charged_amount
                call_record.ended_at = effective_ended_at
                call_record.effective_ended_at = effective_ended_at
                call_record.end_basis = "force_exit"
                call_record.force_exit_user_id = force_exit_decision.force_exit_user_id
                if not getattr(call_record, "income_certified_user_id", None):
                    call_record.income_certified_user_id = (
                        _resolve_income_certified_user_id_for_call(
                            caller_id=int(call_record.caller_id),
                            callee_id=int(call_record.callee_id),
                            payer_id=payer_id,
                            certified_user_ids=certified_user_ids,
                        )
                        or None
                    )
                service_fee_adjustment = await apply_call_service_fee_final_adjustment(
                    call_record=call_record,
                    conn=conn,
                    payer_id=payer_id,
                )
                if (
                    service_fee_adjustment.payer_balance_changed
                    and payer_id is not None
                    and payer_id > 0
                    and not any(
                        int(existing.id) == int(call_record.id) and existing_payer_id == payer_id
                        for existing, existing_payer_id in charged_records
                    )
                ):
                    charged_records.append((call_record, payer_id))
                settlement = await settle_call_certified_user_income_once(
                    call_record=call_record,
                    conn=conn,
                    total_fee=charged_amount,
                    payer_id=payer_id,
                )
                if settlement.settled and settlement.certified_user_id > 0:
                    certified_user_balance_pushes.append(settlement.certified_user_id)
                await call_record.save(using_db=conn)
                ended_records.append(call_record)
                continue

            duration = int(
                max(
                    0,
                    (to_utc_aware(now_local_naive()) - to_utc_aware(call_record.connected_at)).total_seconds(),
                )
            )
            deducted_minutes = int(call_record.deducted_minutes or 0)
            due_minutes = _calc_due_minutes(duration, free_seconds_before_billing)
            next_due = _next_due_second(deducted_minutes, free_seconds_before_billing)
            overdue_seconds = duration - next_due

            if due_minutes <= deducted_minutes:
                continue
            if overdue_seconds < config.renew_grace_seconds:
                continue

            payer_id = _resolve_payer_id_from_record(r, call_record)
            if payer_id is None:
                call_record.last_renew_at = now_local_naive()
                await call_record.save(using_db=conn)
                continue

            to_charge_minutes = due_minutes - deducted_minutes
            charge_amount = to_charge_minutes * int(call_record.call_price or 0)

            payer = await AppUser.filter(id=payer_id).using_db(conn).select_for_update().first()
            if not payer or payer.coins < charge_amount:
                call_record.status = "ended"
                call_record.end_reason = "balance_empty"
                call_record.duration = duration
                call_record.deducted_minutes = deducted_minutes
                call_record.total_fee = int(call_record.deducted_amount or 0)
                call_record.ended_at = now_local_naive()
                call_record.effective_ended_at = call_record.ended_at
                call_record.end_basis = "balance_empty"
                call_record.force_exit_user_id = None
                if not getattr(call_record, "income_certified_user_id", None):
                    call_record.income_certified_user_id = (
                        _resolve_income_certified_user_id_for_call(
                            caller_id=int(call_record.caller_id),
                            callee_id=int(call_record.callee_id),
                            payer_id=payer_id,
                            certified_user_ids=certified_user_ids,
                        )
                        or None
                    )
                service_fee_adjustment = await apply_call_service_fee_final_adjustment(
                    call_record=call_record,
                    conn=conn,
                    payer_id=payer_id,
                    payer=payer,
                )
                if service_fee_adjustment.payer_balance_changed and not any(
                    int(existing.id) == int(call_record.id) and existing_payer_id == payer_id
                    for existing, existing_payer_id in charged_records
                ):
                    charged_records.append((call_record, payer_id))
                settlement = await settle_call_certified_user_income_once(
                    call_record=call_record,
                    conn=conn,
                    total_fee=int(call_record.deducted_amount or 0),
                    payer_id=payer_id,
                )
                if settlement.settled and settlement.certified_user_id > 0:
                    certified_user_balance_pushes.append(settlement.certified_user_id)
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

            updated = (
                await AppUser.filter(
                    id=payer_id,
                    coins__gte=charge_amount,
                )
                .using_db(conn)
                .update(coins=_build_coins_decrement_expr(charge_amount))
            )
            if updated == 0:
                call_record.status = "ended"
                call_record.end_reason = "balance_empty"
                call_record.duration = duration
                call_record.deducted_minutes = deducted_minutes
                call_record.total_fee = int(call_record.deducted_amount or 0)
                call_record.ended_at = now_local_naive()
                call_record.effective_ended_at = call_record.ended_at
                call_record.end_basis = "balance_empty"
                call_record.force_exit_user_id = None
                if not getattr(call_record, "income_certified_user_id", None):
                    call_record.income_certified_user_id = (
                        _resolve_income_certified_user_id_for_call(
                            caller_id=int(call_record.caller_id),
                            callee_id=int(call_record.callee_id),
                            payer_id=payer_id,
                            certified_user_ids=certified_user_ids,
                        )
                        or None
                    )
                service_fee_adjustment = await apply_call_service_fee_final_adjustment(
                    call_record=call_record,
                    conn=conn,
                    payer_id=payer_id,
                )
                if service_fee_adjustment.payer_balance_changed and not any(
                    int(existing.id) == int(call_record.id) and existing_payer_id == payer_id
                    for existing, existing_payer_id in charged_records
                ):
                    charged_records.append((call_record, payer_id))
                settlement = await settle_call_certified_user_income_once(
                    call_record=call_record,
                    conn=conn,
                    total_fee=int(call_record.deducted_amount or 0),
                    payer_id=payer_id,
                )
                if settlement.settled and settlement.certified_user_id > 0:
                    certified_user_balance_pushes.append(settlement.certified_user_id)
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
            payer.coins = quantize_decimal_2(quantize_decimal_2(payer.coins) - charge_amount)
            await _apply_incremental_call_service_fee(
                call_record=call_record,
                payer=payer,
                conn=conn,
            )
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

    return ended_records, charged_records, certified_user_balance_pushes


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


async def _ws_push_call_force_exit(call_record: CallRecord) -> None:
    """推送强退结束事件到 WebSocket（fire-and-forget）。"""
    try:
        from app.websocket import events as ws_events

        await ws_events.push_call_ended(
            caller_id=int(call_record.caller_id),
            callee_id=int(call_record.callee_id),
            call_id=int(call_record.id),
            end_reason="force_exit",
        )
    except Exception as e:  # noqa: BLE001
        logger.warning("ws push force_exit failed: {}", str(e))


async def _ws_push_balance_updated_for_charge(payer_id: int) -> None:
    """Watchdog 扣费成功后推送余额更新给付费方（fire-and-forget）。"""
    try:
        await publish_balance_changed(int(payer_id), source="call_billing")
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
