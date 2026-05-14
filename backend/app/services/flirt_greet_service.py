from datetime import datetime, timedelta

FLIRT_GREET_COOLDOWN_SECONDS = 10
_GREET_RESERVE_LUA = """
local cooldown_ttl = redis.call('TTL', KEYS[2])
if cooldown_ttl > 0 then
    return {-1, cooldown_ttl}
end
local count = redis.call('INCR', KEYS[1])
if count == 1 then
    redis.call('EXPIRE', KEYS[1], ARGV[1])
end
if count > tonumber(ARGV[2]) then
    redis.call('DECR', KEYS[1])
    return {0, 0}
end
return {count, 0}
"""


def _now_local(now: datetime | None = None) -> datetime:
    return now or datetime.now()


def build_greet_daily_key(user_id: int, *, now: datetime | None = None) -> str:
    current = _now_local(now)
    return f"flirt:greet:daily:{current.strftime('%Y%m%d')}:{int(user_id)}"


def build_greet_cooldown_key(user_id: int) -> str:
    return f"flirt:greet:cooldown:{int(user_id)}"


def calculate_greet_daily_ttl(*, now: datetime | None = None) -> int:
    current = _now_local(now)
    tomorrow = (current + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    return max(1, int((tomorrow - current).total_seconds()))


def build_greet_quota_payload(*, daily_limit: int, used: int, cooldown_seconds: int) -> dict:
    limit = max(0, int(daily_limit or 0))
    used_count = max(0, int(used or 0))
    enabled = limit > 0
    return {
        "daily_limit": limit,
        "used": used_count,
        "remaining": max(0, limit - used_count) if enabled else 0,
        "enabled": enabled,
        "cooldown_seconds": max(0, int(cooldown_seconds or 0)),
    }


async def get_greet_quota(redis, *, user_id: int, daily_limit: int) -> dict:
    daily_key = build_greet_daily_key(user_id)
    cooldown_key = build_greet_cooldown_key(user_id)
    raw_used = await redis.get(daily_key)
    raw_ttl = await redis.ttl(cooldown_key)
    try:
        used = int(raw_used or 0)
    except (TypeError, ValueError):
        used = 0
    cooldown_seconds = int(raw_ttl or 0) if int(raw_ttl or 0) > 0 else 0
    return build_greet_quota_payload(
        daily_limit=daily_limit,
        used=used,
        cooldown_seconds=cooldown_seconds,
    )


async def reserve_greet_quota(redis, *, user_id: int, daily_limit: int) -> tuple[str, dict]:
    quota = await get_greet_quota(redis, user_id=user_id, daily_limit=daily_limit)
    if not quota["enabled"]:
        return "disabled", quota
    if quota["cooldown_seconds"] > 0:
        return "cooldown", quota
    if quota["remaining"] <= 0:
        return "exhausted", quota

    daily_key = build_greet_daily_key(user_id)
    cooldown_key = build_greet_cooldown_key(user_id)
    ttl = calculate_greet_daily_ttl()
    result = await redis.eval(_GREET_RESERVE_LUA, 2, daily_key, cooldown_key, ttl, int(daily_limit))
    count = int(result[0])
    cooldown_seconds = int(result[1])
    if count == -1:
        return "cooldown", build_greet_quota_payload(
            daily_limit=daily_limit,
            used=quota["used"],
            cooldown_seconds=cooldown_seconds,
        )
    if count == 0:
        return "exhausted", build_greet_quota_payload(
            daily_limit=daily_limit,
            used=daily_limit,
            cooldown_seconds=0,
        )
    return "reserved", build_greet_quota_payload(
        daily_limit=daily_limit,
        used=count,
        cooldown_seconds=0,
    )


async def release_greet_quota(redis, *, user_id: int) -> None:
    daily_key = build_greet_daily_key(user_id)
    raw_used = await redis.get(daily_key)
    try:
        used = int(raw_used or 0)
    except (TypeError, ValueError):
        used = 0
    if used > 0:
        await redis.decr(daily_key)


async def set_greet_cooldown(redis, *, user_id: int, cooldown_seconds: int = FLIRT_GREET_COOLDOWN_SECONDS) -> None:
    seconds = max(0, int(cooldown_seconds or 0))
    if seconds <= 0:
        return
    await redis.set(build_greet_cooldown_key(user_id), "1", ex=seconds)
