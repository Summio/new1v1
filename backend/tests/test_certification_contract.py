import importlib.util
from pathlib import Path

import pytest
from pydantic import ValidationError


ROOT = Path(__file__).resolve().parents[1]
APP_USER_SCHEMA = ROOT / "app" / "schemas" / "app_user.py"
APP_API_SCHEMA = ROOT / "app" / "schemas" / "app_api.py"
APP_USER_MODEL = ROOT / "app" / "models" / "app_user.py"
ADMIN_MODEL = ROOT / "app" / "models" / "admin.py"
SYSTEM_SCHEMA = ROOT / "app" / "schemas" / "system.py"
INIT_APP = ROOT / "app" / "core" / "init_app.py"
BOOTSTRAP = ROOT / "app" / "api" / "v1" / "app" / "bootstrap.py"
APP_ROUTERS = ROOT / "app" / "api" / "v1" / "app" / "__init__.py"
SYSTEM_CONFIG_VIEW = ROOT / "web" / "src" / "views" / "system" / "config" / "index.vue"
APP_USER_VIEW = ROOT / "web" / "src" / "views" / "operation" / "app-user" / "index.vue"
CALL_RECORD_VIEW = ROOT / "web" / "src" / "views" / "operation" / "call-record" / "index.vue"
CERTIFIED_CALL_PRICE_CONFIG_VIEW = (
    ROOT / "web" / "src" / "views" / "system" / "certified-call-price-config" / "index.vue"
)
CERTIFICATION_CENTER_PAGE = ROOT.parent / "huanxi" / "lib" / "modules" / "home" / "certification_center_page.dart"
AUTH_PROVIDER = ROOT.parent / "huanxi" / "lib" / "app" / "providers" / "auth_provider.dart"
MIGRATIONS_DIR = ROOT / "migrations" / "models"


def _load_schema_module():
    spec = importlib.util.spec_from_file_location("app_user_schema", APP_USER_SCHEMA)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_system_schema_module():
    spec = importlib.util.spec_from_file_location("system_schema", SYSTEM_SCHEMA)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_certification_apply_schema_replaces_legacy_anchor_apply_schema() -> None:
    module = _load_schema_module()

    payload = module.CertificationApplyIn(
        face_photo_url="/uploads/profile/1/certification/face.jpg"
    )
    assert payload.face_photo_url == "/uploads/profile/1/certification/face.jpg"

    with pytest.raises(ValidationError):
        module.CertificationApplyIn()

    assert not hasattr(module, "AnchorApplyIn")
    assert not hasattr(module, "AnchorApplyReviewIn")


def test_app_user_model_uses_certification_fields_only() -> None:
    content = APP_USER_MODEL.read_text(encoding="utf-8")
    assert "is_certified_user" in content
    assert "certification_status" in content
    assert "certified_call_price" in content
    assert "is_anchor" not in content
    assert "anchor_" not in content


def test_bootstrap_returns_certified_call_price_tiers() -> None:
    content = BOOTSTRAP.read_text(encoding="utf-8")
    assert "certified_call_price_tiers" in content
    assert "[0, 100, 200, 300, 500]" in content


def test_system_config_page_exposes_certified_call_price_tiers() -> None:
    content = SYSTEM_CONFIG_VIEW.read_text(encoding="utf-8")

    assert "认证用户通话价格档位" in content
    assert "getCertifiedCallPriceConfig" in content
    assert "updateCertifiedCallPriceConfig" in content
    assert "新增档位" in content
    assert "请至少保留一个收费档位" in content


def test_certified_call_price_config_requires_paid_tier() -> None:
    module = _load_system_schema_module()

    with pytest.raises(ValidationError):
        module.CertifiedCallPriceConfigIn(tiers=[0])


def test_call_price_unit_is_coin_per_minute_across_active_surfaces() -> None:
    checked_files = [
        APP_USER_SCHEMA,
        SYSTEM_SCHEMA,
        APP_USER_MODEL,
        ADMIN_MODEL,
        SYSTEM_CONFIG_VIEW,
        APP_USER_VIEW,
        CALL_RECORD_VIEW,
        CERTIFICATION_CENTER_PAGE,
    ]
    combined = "\n".join(path.read_text(encoding="utf-8") for path in checked_files)

    assert "金币/分钟" in combined
    assert "分/分钟" not in combined
    assert "元/分钟" not in combined
    assert "price / 100" not in combined
    assert "${value / 100}元/分钟" not in combined


def test_certified_call_price_config_independent_page_removed() -> None:
    init_text = INIT_APP.read_text(encoding="utf-8")

    assert not CERTIFIED_CALL_PRICE_CONFIG_VIEW.exists()
    assert '"component": "/system/certified-call-price-config"' not in init_text
    assert 'await Menu.filter(path="certified-call-price-config").delete()' in init_text
    assert 'await Menu.filter(component="/system/certified-call-price-config").delete()' in init_text


def test_app_certification_center_uses_dynamic_coin_name_for_call_price() -> None:
    content = CERTIFICATION_CENTER_PAGE.read_text(encoding="utf-8")

    assert "tokenNamesProvider" in content
    assert "coinName" in content
    assert "return '$price$coinName/分钟';" in content
    assert "元/分钟" not in content
    assert "price / 100" not in content


def test_app_certification_center_hides_free_tier_for_certified_users() -> None:
    content = CERTIFICATION_CENTER_PAGE.read_text(encoding="utf-8")

    assert "configuredTiers.where((tier) => tier > 0).toList()" in content
    assert "暂无可用通话价格，请联系平台配置" in content
    assert "? const [0, 100, 200, 300, 500]" not in content


def test_app_init_does_not_hardcode_paid_call_price_tiers() -> None:
    content = AUTH_PROVIDER.read_text(encoding="utf-8")

    assert "this.certifiedCallPriceTiers = const []" in content
    assert ": <int>[0, 100, 200, 300, 500]" not in content


def test_app_routes_expose_certification_apply_not_legacy_anchor_apply() -> None:
    content = APP_ROUTERS.read_text(encoding="utf-8")
    assert "certification" in content
    assert "anchor_apply" not in content


def test_app_api_request_schemas_do_not_accept_legacy_anchor_target_fields() -> None:
    content = APP_API_SCHEMA.read_text(encoding="utf-8")
    assert "target_user_id" in content
    assert "certified_user_id" not in content
    assert "certified_user_id" not in content
    assert "validate_certified_user_id" not in content


def test_migration_moves_legacy_anchor_columns_to_certification_columns_and_drops_old_columns() -> None:
    migration_files = sorted(MIGRATIONS_DIR.glob("*certification*.py"))
    assert migration_files, "expected certification migration file"
    content = "\n".join(path.read_text(encoding="utf-8") for path in migration_files)
    assert "is_certified_user" in content
    assert "certification_status" in content
    assert "certified_call_price" in content
    assert "DROP COLUMN `is_anchor`" in content or "DROP COLUMN is_anchor" in content
    assert "DROP COLUMN `anchor_call_price`" in content or "DROP COLUMN anchor_call_price" in content
    assert "THEN 100" in content


def test_business_code_no_longer_reads_removed_legacy_is_anchor_attribute() -> None:
    checked_files = [
        ROOT / "app" / "api" / "v1" / "moments" / "moments.py",
        ROOT / "app" / "api" / "v1" / "app" / "moment.py",
        ROOT / "app" / "services" / "ranking_service.py",
    ]
    for path in checked_files:
        content = path.read_text(encoding="utf-8")
        assert ".is_anchor" not in content

