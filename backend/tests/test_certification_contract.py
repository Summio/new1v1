import importlib.util
from pathlib import Path

import pytest
from pydantic import ValidationError


ROOT = Path(__file__).resolve().parents[1]
APP_USER_SCHEMA = ROOT / "app" / "schemas" / "app_user.py"
APP_API_SCHEMA = ROOT / "app" / "schemas" / "app_api.py"
APP_USER_MODEL = ROOT / "app" / "models" / "app_user.py"
BOOTSTRAP = ROOT / "app" / "api" / "v1" / "app" / "bootstrap.py"
APP_ROUTERS = ROOT / "app" / "api" / "v1" / "app" / "__init__.py"
MIGRATIONS_DIR = ROOT / "migrations" / "models"


def _load_schema_module():
    spec = importlib.util.spec_from_file_location("app_user_schema", APP_USER_SCHEMA)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_certification_apply_schema_replaces_anchor_apply_schema() -> None:
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


def test_app_routes_expose_certification_apply_not_anchor_apply() -> None:
    content = APP_ROUTERS.read_text(encoding="utf-8")
    assert "certification" in content
    assert "anchor_apply" not in content


def test_app_api_request_schemas_do_not_accept_old_anchor_target_fields() -> None:
    content = APP_API_SCHEMA.read_text(encoding="utf-8")
    assert "target_user_id" in content
    assert "anchor_user_id" not in content
    assert "anchor_id" not in content
    assert "validate_anchor_user_id" not in content


def test_migration_moves_anchor_columns_to_certification_columns_and_drops_old_columns() -> None:
    migration_files = sorted(MIGRATIONS_DIR.glob("*certification*.py"))
    assert migration_files, "expected certification migration file"
    content = "\n".join(path.read_text(encoding="utf-8") for path in migration_files)
    assert "is_certified_user" in content
    assert "certification_status" in content
    assert "certified_call_price" in content
    assert "DROP COLUMN `is_anchor`" in content or "DROP COLUMN is_anchor" in content
    assert "DROP COLUMN `anchor_call_price`" in content or "DROP COLUMN anchor_call_price" in content
    assert "THEN 100" in content
