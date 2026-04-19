from __future__ import annotations

from typing import TypedDict

from app.core.redis import get_redis
from app.log import logger

_CALL_PRESENCE_TTL_SECONDS = 60 * 10


class CallPresenceSnapshot(TypedDict):
    caller_last_seen_ms: int | None
    callee_last_seen_ms: int | None
    caller_left_candidate_ms: int | None
    callee_left_candidate_ms: int | None


def _presence_key(call_id: int) -> str:
    return f"call:presence:{int(call_id)}"


def _last_seen_field(role: str) -> str:
    if role not in {"caller", "callee"}:
        raise ValueError(f"invalid role: {role}")
    return f"{role}_last_seen_ms"


def _left_candidate_field(role: str) -> str:
    if role not in {"caller", "callee"}:
        raise ValueError(f"invalid role: {role}")
    return f"{role}_left_candidate_ms"


def _to_int_or_none(raw: str | int | None) -> int | None:
    if raw is None:
        return None
    try:
        return int(raw)
    except (TypeError, ValueError):
        return None


async def update_last_seen(
    *,
    call_id: int,
    user_id: int,
    role: str,
    now_ms: int,
) -> None:
    redis = await get_redis()
    key = _presence_key(call_id)
    try:
        await redis.hset(key, mapping={_last_seen_field(role): int(now_ms)})
        # 恢复心跳后清理离场候选，避免抖动导致误强退。
        await redis.hdel(key, _left_candidate_field(role))
        await redis.expire(key, _CALL_PRESENCE_TTL_SECONDS)
    except Exception as e:  # noqa: BLE001
        logger.warning(
            "call_presence update_last_seen failed: call_id={} user_id={} role={} error={}",
            call_id,
            user_id,
            role,
            str(e),
        )


async def mark_left_candidate(*, call_id: int, role: str, now_ms: int) -> None:
    redis = await get_redis()
    key = _presence_key(call_id)
    await redis.hset(key, mapping={_left_candidate_field(role): int(now_ms)})
    await redis.expire(key, _CALL_PRESENCE_TTL_SECONDS)


async def clear_left_candidate(*, call_id: int, role: str) -> None:
    redis = await get_redis()
    await redis.hdel(_presence_key(call_id), _left_candidate_field(role))


async def get_snapshot(*, call_id: int) -> CallPresenceSnapshot:
    redis = await get_redis()
    raw = await redis.hgetall(_presence_key(call_id))
    return {
        "caller_last_seen_ms": _to_int_or_none(raw.get("caller_last_seen_ms")),
        "callee_last_seen_ms": _to_int_or_none(raw.get("callee_last_seen_ms")),
        "caller_left_candidate_ms": _to_int_or_none(
            raw.get("caller_left_candidate_ms")
        ),
        "callee_left_candidate_ms": _to_int_or_none(
            raw.get("callee_left_candidate_ms")
        ),
    }
