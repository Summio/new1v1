"""余额变更后的统一 WebSocket 发布与通话余额预警。"""

from __future__ import annotations

from decimal import Decimal

from app.core.redis import get_redis
from app.log import logger
from app.models import AppUser, CallRecord
from app.services.gift_income_service import decimal_to_float_2
from app.websocket import events as ws_events

BALANCE_LOW_REMINDER_TTL_SECONDS = 30


def _balance_low_key(call_id: int, user_id: int) -> str:
    return f"call:{int(call_id)}:balance_low:{int(user_id)}"


async def publish_balance_changed(user_id: int, *, source: str) -> None:
    """推送用户最新余额，并在通话中余额不足下一分钟时发出预警。"""
    user = await AppUser.filter(id=int(user_id)).first()
    if not user:
        return

    coins = user.coins
    await ws_events.push_balance_update(
        user_id=int(user_id),
        coins=decimal_to_float_2(coins),
        diamonds=decimal_to_float_2(user.diamonds),
    )
    await maybe_push_call_balance_low_for_user(
        user_id=int(user_id),
        coins=coins,
        source=source,
    )


async def maybe_push_call_balance_low_for_user(
    *,
    user_id: int,
    source: str,
    coins: Decimal | int | float | None = None,
) -> None:
    """检查用户正在付费的通话是否已经不足下一分钟费用。"""
    normalized_user_id = int(user_id)
    if coins is None:
        user = await AppUser.filter(id=normalized_user_id).first()
        if not user:
            return
        coins = user.coins

    calls = await CallRecord.filter(
        status="ongoing",
        payer_user_id=normalized_user_id,
    ).values("id", "caller_id", "callee_id", "call_price")

    current_coins = Decimal(str(coins))
    for call in calls:
        call_id = int(call["id"])
        call_price = int(call.get("call_price") or 0)
        if call_price <= 0:
            continue

        key = _balance_low_key(call_id, normalized_user_id)
        if current_coins >= Decimal(call_price):
            if source != "call_heartbeat":
                await _clear_balance_low_throttle(key)
            continue

        if not await _should_push_balance_low(key):
            continue

        await ws_events.push_call_balance_low(
            caller_id=int(call["caller_id"]),
            callee_id=int(call["callee_id"]),
            payer_user_id=normalized_user_id,
            call_id=call_id,
            coins=decimal_to_float_2(current_coins),
            required_coins=call_price,
            source=source,
        )


async def _should_push_balance_low(key: str) -> bool:
    try:
        redis = await get_redis()
        return bool(
            await redis.set(
                key,
                "1",
                nx=True,
                ex=BALANCE_LOW_REMINDER_TTL_SECONDS,
            )
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("balance low throttle degraded: {}", str(exc))
        return True


async def _clear_balance_low_throttle(key: str) -> None:
    try:
        redis = await get_redis()
        await redis.delete(key)
    except Exception as exc:  # noqa: BLE001
        logger.warning("balance low throttle clear failed: {}", str(exc))
