import json
from collections.abc import Awaitable, Callable

from app.core.redis import get_redis
from app.models import AppUser

RECOMMENDED_USER_IDS_CACHE_KEY = "moment:recommended_user_ids"
RECOMMENDED_USER_IDS_CACHE_TTL_SECONDS = 45


async def _load_recommended_user_ids_from_db() -> list[int]:
    rows = await AppUser.filter(is_recommended=True).values_list("id", flat=True)
    return [int(user_id) for user_id in rows]


async def get_recommended_user_ids(
    *,
    load_from_db: Callable[[], Awaitable[list[int]]] | None = None,
) -> list[int]:
    loader = load_from_db or _load_recommended_user_ids_from_db
    try:
        redis = await get_redis()
        cached = await redis.get(RECOMMENDED_USER_IDS_CACHE_KEY)
        if cached is not None:
            data = json.loads(cached)
            if isinstance(data, list):
                return [int(user_id) for user_id in data]
    except Exception:
        return await loader()

    user_ids = await loader()
    try:
        await redis.setex(
            RECOMMENDED_USER_IDS_CACHE_KEY,
            RECOMMENDED_USER_IDS_CACHE_TTL_SECONDS,
            json.dumps(user_ids, ensure_ascii=False),
        )
    except Exception:
        pass
    return user_ids


async def invalidate_recommended_user_ids_cache() -> None:
    try:
        redis = await get_redis()
        await redis.delete(RECOMMENDED_USER_IDS_CACHE_KEY)
    except Exception:
        pass
