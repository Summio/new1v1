import inspect

from app.api.v1.app.certified_user import certified_user_list
from app.schemas.app_user import AppUserAdminUpdateIn, AppUserProfileUpdateIn


def test_certified_user_list_supports_keyword_query() -> None:
    params = inspect.signature(certified_user_list).parameters

    assert "keyword" in params


def test_certified_user_list_keyword_keeps_gender_filter_available() -> None:
    params = inspect.signature(certified_user_list).parameters

    assert "gender" in params


def test_certified_user_list_keyword_searches_all_normal_users() -> None:
    source = inspect.getsource(certified_user_list)

    assert 'filters = {"status": "normal"}' in source
    assert 'filters["is_certified_user"] = True' in source
    assert '"is_certified_user": True' not in source


def test_profile_update_accepts_signature() -> None:
    assert "signature" in AppUserProfileUpdateIn.model_fields


def test_admin_update_accepts_signature() -> None:
    assert "signature" in AppUserAdminUpdateIn.model_fields


def test_certified_user_list_returns_cover_and_profile_detail_fields() -> None:
    source = inspect.getsource(certified_user_list)

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
