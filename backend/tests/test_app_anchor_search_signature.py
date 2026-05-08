import inspect

from app.api.v1.app.anchor import anchor_list
from app.schemas.app_user import AppUserAdminUpdateIn, AppUserProfileUpdateIn


def test_anchor_list_supports_keyword_query() -> None:
    params = inspect.signature(anchor_list).parameters

    assert "keyword" in params


def test_anchor_list_keyword_keeps_gender_filter_available() -> None:
    params = inspect.signature(anchor_list).parameters

    assert "gender" in params


def test_profile_update_accepts_signature() -> None:
    assert "signature" in AppUserProfileUpdateIn.model_fields


def test_admin_update_accepts_signature() -> None:
    assert "signature" in AppUserAdminUpdateIn.model_fields


def test_anchor_list_returns_cover_and_profile_detail_fields() -> None:
    source = inspect.getsource(anchor_list)

    assert "cover_url__not_isnull" in source
    for field in (
        '"cover_url"',
        '"album_photos"',
        '"signature"',
        '"birth_date"',
        '"height_cm"',
        '"weight_kg"',
        '"location_city"',
        '"status"',
    ):
        assert field in source

