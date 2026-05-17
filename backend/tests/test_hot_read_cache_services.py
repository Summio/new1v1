import sys
from pathlib import Path

import pytest

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))


class FakeRedis:
    def __init__(self):
        self.store = {}
        self.setex_calls = []
        self.delete_calls = []

    async def get(self, key):
        return self.store.get(key)

    async def setex(self, key, ttl, value):
        self.setex_calls.append((key, ttl, value))
        self.store[key] = value
        return True

    async def delete(self, *keys):
        self.delete_calls.append(keys)
        deleted = 0
        for key in keys:
            if key in self.store:
                deleted += 1
                del self.store[key]
        return deleted


@pytest.mark.asyncio
async def test_recommended_user_ids_cache_hits_and_invalidates(monkeypatch):
    from app.services import recommended_user_cache

    redis = FakeRedis()
    calls = 0

    async def fake_get_redis():
        return redis

    async def fake_loader():
        nonlocal calls
        calls += 1
        return [3, 1, 2]

    monkeypatch.setattr(recommended_user_cache, "get_redis", fake_get_redis)

    first = await recommended_user_cache.get_recommended_user_ids(load_from_db=fake_loader)
    second = await recommended_user_cache.get_recommended_user_ids(load_from_db=fake_loader)
    await recommended_user_cache.invalidate_recommended_user_ids_cache()

    assert first == [3, 1, 2]
    assert second == [3, 1, 2]
    assert calls == 1
    assert redis.setex_calls[0][1] == recommended_user_cache.RECOMMENDED_USER_IDS_CACHE_TTL_SECONDS
    assert redis.delete_calls == [(recommended_user_cache.RECOMMENDED_USER_IDS_CACHE_KEY,)]


@pytest.mark.asyncio
async def test_blocked_user_ids_cache_hits_and_invalidates(monkeypatch):
    from app.services import user_block_service

    redis = FakeRedis()
    calls = 0

    async def fake_get_redis():
        return redis

    async def fake_loader(current_user_id):
        nonlocal calls
        calls += 1
        assert current_user_id == 9
        return [4, 7]

    monkeypatch.setattr(user_block_service, "get_redis", fake_get_redis)
    monkeypatch.setattr(user_block_service, "_load_excluded_blocked_user_ids", fake_loader)

    first = await user_block_service.exclude_blocked_user_ids(9)
    second = await user_block_service.exclude_blocked_user_ids(9)
    await user_block_service.invalidate_blocked_user_ids_cache(9, 4)

    assert first == [4, 7]
    assert second == [4, 7]
    assert calls == 1
    assert redis.setex_calls[0][1] == user_block_service.BLOCKED_USER_IDS_CACHE_TTL_SECONDS
    assert redis.delete_calls == [
        (
            user_block_service.blocked_user_ids_cache_key(9),
            user_block_service.blocked_user_ids_cache_key(4),
        )
    ]
