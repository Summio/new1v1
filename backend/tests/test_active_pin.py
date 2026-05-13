import pytest


@pytest.mark.asyncio
async def test_load_active_pin_cooldown_minutes_defaults_and_clamps(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import active_pin_service

    values = iter(["", "abc", "-3", "20000", "0", "45"])

    async def fake_get_value(key: str, default: str = "") -> str:
        assert key == "active_pin_cooldown_minutes"
        assert default == "60"
        return next(values)

    monkeypatch.setattr(active_pin_service.SystemConfig, "get_value", fake_get_value)

    assert await active_pin_service.load_active_pin_cooldown_minutes() == 60
    assert await active_pin_service.load_active_pin_cooldown_minutes() == 60
    assert await active_pin_service.load_active_pin_cooldown_minutes() == 0
    assert await active_pin_service.load_active_pin_cooldown_minutes() == 10080
    assert await active_pin_service.load_active_pin_cooldown_minutes() == 0
    assert await active_pin_service.load_active_pin_cooldown_minutes() == 45


@pytest.mark.asyncio
async def test_consume_active_pin_cooldown_writes_nx_key(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import active_pin_service

    class FakeRedis:
        def __init__(self) -> None:
            self.calls: list[tuple] = []

        async def set(self, key, value, nx=False, ex=None):
            self.calls.append(("set", key, value, nx, ex))
            return True

    redis = FakeRedis()

    async def fake_get_redis():
        return redis

    monkeypatch.setattr(active_pin_service, "get_redis", fake_get_redis)
    monkeypatch.setattr(active_pin_service, "_now_ms", lambda: 123456)

    result = await active_pin_service.try_consume_active_pin_cooldown(user_id=9, cooldown_minutes=30)

    assert result.allowed is True
    assert result.remaining_seconds == 0
    assert result.pinned_at_ms == 123456
    assert redis.calls == [("set", "active_pin:cooldown:9", "123456", True, 1800)]


@pytest.mark.asyncio
async def test_consume_active_pin_cooldown_reports_remaining_seconds(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import active_pin_service

    class FakeRedis:
        async def set(self, key, value, nx=False, ex=None):
            return False

        async def ttl(self, key):
            assert key == "active_pin:cooldown:9"
            return 1234

    async def fake_get_redis():
        return FakeRedis()

    monkeypatch.setattr(active_pin_service, "get_redis", fake_get_redis)
    monkeypatch.setattr(active_pin_service, "_now_ms", lambda: 123456)

    result = await active_pin_service.try_consume_active_pin_cooldown(user_id=9, cooldown_minutes=30)

    assert result.allowed is False
    assert result.remaining_seconds == 1234
    assert result.pinned_at_ms == 123456


@pytest.mark.asyncio
async def test_consume_active_pin_cooldown_zero_minutes_skips_redis(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.services import active_pin_service

    async def fail_get_redis():
        raise AssertionError("Redis should not be used when cooldown is disabled")

    monkeypatch.setattr(active_pin_service, "get_redis", fail_get_redis)
    monkeypatch.setattr(active_pin_service, "_now_ms", lambda: 123456)

    result = await active_pin_service.try_consume_active_pin_cooldown(user_id=9, cooldown_minutes=0)

    assert result.allowed is True
    assert result.remaining_seconds == 0
    assert result.pinned_at_ms == 123456


def test_active_pin_route_contract_guards_before_consuming_cooldown() -> None:
    import inspect

    from app.api.v1.app import certified_user

    source = inspect.getsource(certified_user.active_pin_certified_user)

    assert 'msg="仅真人认证用户可使用置顶"' in source
    assert 'msg="当前为勿扰状态，请关闭勿扰后再置顶"' in source
    assert 'msg="请先保持在线后再置顶"' in source
    assert "is_online" in source
    assert "try_consume_active_pin_cooldown" in source
    assert "mark_online_since" in source
    assert source.index("video_dnd_enabled") < source.index("try_consume_active_pin_cooldown")
    assert source.index("is_online") < source.index("try_consume_active_pin_cooldown")


def test_admin_system_config_exposes_active_pin_cooldown() -> None:
    from pathlib import Path

    repo_root = Path(__file__).resolve().parents[2]
    view_text = (repo_root / "backend/web/src/views/system/config/index.vue").read_text(encoding="utf-8")

    assert "曝光配置" in view_text
    assert "活跃页置顶冷却时间" in view_text
    assert "active_pin_cooldown_minutes" in view_text
    assert "defaultValue: '60'" in view_text
    assert "max: 10080" in view_text
