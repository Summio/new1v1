import sys
from datetime import date, timedelta
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.core.profile_basic_fields import (  # noqa: E402
    normalize_birth_date,
    normalize_height_cm,
    normalize_weight_kg,
)
from app.schemas.app_user import (  # noqa: E402
    AppUserAdminUpdateIn,
    AppUserProfileUpdateIn,
)


def test_profile_basic_fields_accept_boundaries_and_empty_values() -> None:
    assert normalize_birth_date(None) is None
    assert normalize_birth_date(date(1960, 1, 1)) == date(1960, 1, 1)
    assert normalize_birth_date(date.today()) == date.today()
    assert normalize_height_cm(None) is None
    assert normalize_height_cm(130) == 130
    assert normalize_height_cm(200) == 200
    assert normalize_weight_kg(None) is None
    assert normalize_weight_kg(30) == 30
    assert normalize_weight_kg(100) == 100


def test_profile_basic_fields_reject_invalid_values() -> None:
    assert normalize_birth_date(date(1959, 12, 31)) == "出生日期不能早于1960-01-01"
    assert normalize_birth_date(date.today() + timedelta(days=1)) == "出生日期不能晚于今天"
    assert normalize_height_cm(129) == "身高不合法"
    assert normalize_height_cm(201) == "身高不合法"
    assert normalize_weight_kg(29) == "体重不合法"
    assert normalize_weight_kg(101) == "体重不合法"


def test_profile_update_schemas_do_not_use_range_constraints_for_business_rules() -> None:
    for model in (AppUserProfileUpdateIn, AppUserAdminUpdateIn):
        height_field = model.model_fields["height_cm"]
        weight_field = model.model_fields["weight_kg"]

        assert "130-200" in height_field.description
        assert "30-100" in weight_field.description
        assert "Ge(" not in repr(height_field.metadata)
        assert "Le(" not in repr(height_field.metadata)
        assert "Ge(" not in repr(weight_field.metadata)
        assert "Le(" not in repr(weight_field.metadata)
        kwargs = {"id": 1} if model is AppUserAdminUpdateIn else {}
        model(height_cm=129, weight_kg=101, **kwargs)


def test_profile_update_apis_use_shared_basic_field_validation() -> None:
    app_user_api = (BACKEND_ROOT / "app/api/v1/app/user.py").read_text(encoding="utf-8")
    admin_user_api = (BACKEND_ROOT / "app/api/v1/app_users/app_users.py").read_text(encoding="utf-8")
    shared_validation = (BACKEND_ROOT / "app/core/profile_basic_fields.py").read_text(encoding="utf-8")

    for source in (app_user_api, admin_user_api):
        assert "normalize_birth_date" in source
        assert "normalize_height_cm" in source
        assert "normalize_weight_kg" in source
    assert "出生日期不能早于1960-01-01" in shared_validation
    assert "出生日期不能晚于今天" in shared_validation
    assert "身高不合法" in shared_validation
    assert "体重不合法" in shared_validation


def test_profile_basic_fields_cleanup_migration_exists() -> None:
    migration = BACKEND_ROOT / "migrations/models/56_20260513_normalize_profile_basic_fields.py"
    migration_text = migration.read_text(encoding="utf-8")
    tighten_migration = BACKEND_ROOT / "migrations/models/57_20260513_tighten_profile_basic_fields.py"
    tighten_migration_text = tighten_migration.read_text(encoding="utf-8")

    assert "UPDATE `app_user`" in migration_text
    assert "`birth_date`" in migration_text
    assert "`height_cm`" in migration_text
    assert "`weight_kg`" in migration_text
    assert "'1960-01-01'" in migration_text
    assert "`birth_date` = NULL" in migration_text
    assert "`height_cm` = NULL" in migration_text
    assert "`weight_kg` = NULL" in migration_text
    assert "`height_cm` < 130" in migration_text
    assert "`height_cm` > 200" in migration_text
    assert "`weight_kg` < 30" in migration_text
    assert "`weight_kg` > 100" in migration_text
    assert "'1960-01-01'" in tighten_migration_text
    assert "`birth_date` > CURRENT_DATE" in tighten_migration_text
    assert "`height_cm` > 200" in tighten_migration_text
    assert "`weight_kg` > 100" in tighten_migration_text
