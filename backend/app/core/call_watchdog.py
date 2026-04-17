import asyncio
from datetime import datetime, timedelta, timezone
from dataclasses import dataclass

from app.log import logger
from app.models import CallRecord
from app.models.system_config import SystemConfig
from tortoise.transactions import in_transaction

FREE_SECONDS_BEFORE_BILLING = 10
DEFAULT_POLL_SECONDS = 5
DEFAULT_RING_TIMEOUT_SECONDS = 30
DEFAULT_RENEW_GRACE_SECONDS = 25
MAX_WATCHDOG_SECONDS = 600
MIN_WATCHDOG_SECONDS = 1


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
        renew_grace_seconds=_clamp_seconds(
            _safe_parse_int(grace_raw, DEFAULT_RENEW_GRACE_SECONDS)
        ),
        free_seconds_before_billing=max(0, _safe_parse_int(free_raw, FREE_SECONDS_BEFORE_BILLING)),
    )


def _to_aware(dt: datetime | None) -> datetime:
    if dt is None:
        return datetime.now(timezone.utc)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _calc_due_minutes(duration_seconds: int, free_seconds_before_billing: int) -> int:
    if duration_seconds < free_seconds_before_billing:
        return 0
    return ((duration_seconds - free_seconds_before_billing) // 60) + 1


def _next_due_second(deducted_minutes: int, free_seconds_before_billing: int) -> int:
    # 续费窗口与主计费逻辑保持一致：
    # due_minutes = ((duration - free_seconds_before_billing) // 60) + 1
    # 因此当已扣 N 分钟后，下一个应扣费边界应为 free + N*60 秒。
    return free_seconds_before_billing + max(0, deducted_minutes) * 60


async def _close_timeout_pending(config: WatchdogConfig) -> None:
    timeout_before = datetime.now(timezone.utc) - timedelta(
        seconds=config.ring_timeout_seconds
    )
    await CallRecord.filter(
        status="pending",
        created_at__lt=timeout_before,
    ).update(
        status="ended",
        end_reason="timeout",
        ended_at=datetime.now(timezone.utc),
    )


async def _close_stale_ongoing(config: WatchdogConfig) -> None:
    ids = await CallRecord.filter(status="ongoing").values_list("id", flat=True)
    for call_id in ids:
        async with in_transaction() as conn:
            call_record = (
                await CallRecord.filter(id=call_id, status="ongoing")
                .using_db(conn)
                .select_for_update()
                .first()
            )
            if not call_record:
                continue

            if not call_record.connected_at:
                continue

            duration = int(
                max(0, (datetime.now(timezone.utc) - _to_aware(call_record.connected_at)).total_seconds())
            )
            deducted_minutes = int(call_record.deducted_minutes or 0)
            next_due = _next_due_second(
                deducted_minutes,
                config.free_seconds_before_billing,
            )
            overdue_seconds = duration - next_due
            due_minutes = _calc_due_minutes(
                duration,
                config.free_seconds_before_billing,
            )

            if due_minutes <= deducted_minutes:
                continue
            if overdue_seconds < config.renew_grace_seconds:
                continue

            call_record.status = "ended"
            call_record.end_reason = "network_lost"
            call_record.duration = duration
            call_record.total_fee = int(call_record.deducted_amount or 0)
            call_record.ended_at = datetime.now(timezone.utc)
            await call_record.save(using_db=conn)
            logger.warning(
                "call watchdog closed stale ongoing call_id={} duration={} deducted_minutes={}",
                call_record.id,
                duration,
                deducted_minutes,
            )


async def run_call_watchdog(stop_event: asyncio.Event) -> None:
    logger.info("call watchdog started")
    try:
        while not stop_event.is_set():
            config = WatchdogConfig(
                poll_seconds=DEFAULT_POLL_SECONDS,
                ring_timeout_seconds=DEFAULT_RING_TIMEOUT_SECONDS,
                renew_grace_seconds=DEFAULT_RENEW_GRACE_SECONDS,
                free_seconds_before_billing=FREE_SECONDS_BEFORE_BILLING,
            )
            try:
                config = await _load_watchdog_config()
                await _close_timeout_pending(config)
                await _close_stale_ongoing(config)
            except Exception as e:  # noqa: BLE001
                logger.exception("call watchdog loop error: {}", str(e))
            try:
                await asyncio.wait_for(stop_event.wait(), timeout=config.poll_seconds)
            except asyncio.TimeoutError:
                pass
    finally:
        logger.info("call watchdog stopped")
