import sys
from pathlib import Path

import pytest
from pydantic import ValidationError

BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.models import AppUser  # noqa: E402
from app.schemas.app_user import AppRegisterIn, AppUserAdminUpdateIn, AppUserProfileUpdateIn, GenderType  # noqa: E402


def test_gender_type_only_allows_male_and_female() -> None:
    assert {item.value for item in GenderType} == {"male", "female"}


def test_app_register_defaults_gender_to_male() -> None:
    req = AppRegisterIn(phone="13800138000", password="abc12345")

    assert req.gender == GenderType.MALE


@pytest.mark.parametrize(
    "schema,payload",
    [
        (AppRegisterIn, {"phone": "13800138000", "password": "abc12345", "gender": "secret"}),
        (AppUserProfileUpdateIn, {"gender": "secret"}),
        (AppUserAdminUpdateIn, {"id": 1, "gender": "secret"}),
    ],
)
def test_gender_secret_is_rejected_by_write_schemas(schema, payload) -> None:
    with pytest.raises(ValidationError):
        schema(**payload)


def test_app_user_model_default_gender_is_male() -> None:
    assert AppUser._meta.fields_map["gender"].default == "male"


def test_flutter_gender_entrypoints_no_longer_send_or_offer_secret() -> None:
    checked_files = [
        REPO_ROOT / "backend/app/schemas/app_user.py",
        REPO_ROOT / "backend/app/models/app_user.py",
        REPO_ROOT / "backend/app/schemas/app_api.py",
        REPO_ROOT / "backend/app/api/v1/app/user.py",
        REPO_ROOT / "backend/app/api/v1/app/certified_user.py",
        REPO_ROOT / "backend/app/api/v1/app_users/app_users.py",
        REPO_ROOT / "backend/web/src/views/operation/app-user/index.vue",
        REPO_ROOT / "huanxi/lib/modules/auth/register_page.dart",
        REPO_ROOT / "huanxi/lib/modules/profile/edit_profile_page.dart",
        REPO_ROOT / "huanxi/lib/app/providers/auth_provider.dart",
    ]

    for path in checked_files:
        assert "secret" not in path.read_text(encoding="utf-8")
