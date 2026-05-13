from __future__ import annotations

import time
from dataclasses import dataclass

from app.core.redis import get_redis
from app.models.system_config import SystemConfig

ACTIVE_PIN_COOLDOWN_CONFIG_KEY = "active_pin_cooldown_minutes"
DEFAULT_ACTIVE_PIN_COOLDOWN_MINUTES = 60
MAX_ACTIVE_PIN_COOLDOWN_MINUTES = 10080
ACTIVE_PIN_COOLDOWN_KEY_PREFIX = "active_pin:cooldown:"


@dataclass(frozen=True)
class ActivePinCooldownResult:
    allowed: bool
    remaining_seconds: int
    pinned_at_ms: int


def _now_ms() -> int:
    return int(time.time() * 1000)


def _cooldown_key(user_id: int) -> str:
    return f"{ACTIVE_PIN_COOLDOWN_KEY_PREFIX}{int(user_id)}"


async def load_active_pin_cooldown_minutes() -> int:
    raw_value = await SystemConfig.get_value(
        ACTIVE_PIN_COOLDOWN_CONFIG_KEY,
        str(DEFAULT_ACTIVE_PIN_COOLDOWN_MINUTES),
    )
    try:
        minutes = int(str(raw_value).strip())
    except (TypeError, ValueError):
        minutes = DEFAULT_ACTIVE_PIN_COOLDOWN_MINUTES
    if minutes < 0:
        return 0
    if minutes > MAX_ACTIVE_PIN_COOLDOWN_MINUTES:
        return MAX_ACTIVE_PIN_COOLDOWN_MINUTES
    return minutes


async def try_consume_active_pin_cooldown(*, user_id: int, cooldown_minutes: int) -> ActivePinCooldownResult:
    pinned_at_ms = _now_ms()
    if cooldown_minutes <= 0:
        return ActivePinCooldownResult(
            allowed=True,
            remaining_seconds=0,
            pinned_at_ms=pinned_at_ms,
        )

    redis = await get_redis()
    key = _cooldown_key(user_id)
    ttl_seconds = int(cooldown_minutes) * 60
    acquired = await redis.set(key, str(pinned_at_ms), nx=True, ex=ttl_seconds)
    if acquired:
        return ActivePinCooldownResult(
            allowed=True,
            remaining_seconds=0,
            pinned_at_ms=pinned_at_ms,
        )

    remaining = await redis.ttl(key)
    try:
        remaining_seconds = int(remaining)
    except (TypeError, ValueError):
        remaining_seconds = ttl_seconds
    if remaining_seconds < 0:
        remaining_seconds = ttl_seconds
    return ActivePinCooldownResult(
        allowed=False,
        remaining_seconds=remaining_seconds,
        pinned_at_ms=pinned_at_ms,
    )


async def clear_active_pin_cooldown(user_id: int) -> None:
    redis = await get_redis()
    await redis.delete(_cooldown_key(user_id))
