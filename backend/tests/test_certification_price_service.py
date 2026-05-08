import asyncio
import importlib.util
import sys
import types
from pathlib import Path


def _load_service():
    for name in [
        "app.services.certification_price_service",
        "app.services",
        "app.models",
        "app",
    ]:
        sys.modules.pop(name, None)
    app = types.ModuleType("app")
    app.__path__ = []
    services = types.ModuleType("app.services")
    services.__path__ = []
    models = types.ModuleType("app.models")

    class SystemConfig:
        @classmethod
        async def get_value(cls, _key, default):
            return default

    sys.modules["app"] = app
    sys.modules["app.services"] = services
    models.SystemConfig = SystemConfig
    sys.modules["app.models"] = models
    sys.modules.pop("app.services.certification_price_service", None)
    path = Path(__file__).resolve().parents[1] / "app/services/certification_price_service.py"
    spec = importlib.util.spec_from_file_location("app.services.certification_price_service", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules["app.services.certification_price_service"] = module
    spec.loader.exec_module(module)
    return module


def teardown_function():
    for name in [
        "app.services.certification_price_service",
        "app.services",
        "app.models",
        "app",
    ]:
        sys.modules.pop(name, None)


def test_parse_certified_call_price_tiers_falls_back_to_default() -> None:
    service = _load_service()
    assert service.parse_certified_call_price_tiers("not-json") == [0, 100, 200, 300, 500]


def test_parse_certified_call_price_tiers_deduplicates_and_keeps_free_tier() -> None:
    service = _load_service()
    assert service.parse_certified_call_price_tiers("[300, 100, 100]") == [0, 100, 300]


def test_normalize_certified_call_price_forces_unverified_users_to_free() -> None:
    service = _load_service()
    assert asyncio.run(service.normalize_certified_call_price(price=100, is_certified_user=False)) == 0


def test_normalize_certified_call_price_maps_unknown_verified_price_to_100() -> None:
    service = _load_service()
    assert asyncio.run(service.normalize_certified_call_price(price=666, is_certified_user=True)) == 100


def test_normalize_certified_call_price_uses_configured_paid_tier_when_100_missing(monkeypatch) -> None:
    service = _load_service()

    async def fake_get_tiers():
        return [0, 200, 300]

    monkeypatch.setattr(service, "get_certified_call_price_tiers", fake_get_tiers)
    assert asyncio.run(service.normalize_certified_call_price(price=666, is_certified_user=True)) == 200
