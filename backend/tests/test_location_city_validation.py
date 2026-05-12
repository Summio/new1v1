import re
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.core.china_locations import (  # noqa: E402
    CHINA_PROVINCE_CITY_MAP,
    normalize_location_city,
)


def _parse_flutter_locations() -> dict[str, list[str]]:
    source = (REPO_ROOT / "huanxi/lib/core/data/china_location_data.dart").read_text(encoding="utf-8")
    locations: dict[str, list[str]] = {}
    for match in re.finditer(r"'([^']+)'\s*:\s*\[([\s\S]*?)\]", source):
        province = match.group(1)
        cities = re.findall(r"'([^']+)'", match.group(2))
        locations[province] = cities
    return locations


def test_backend_location_data_matches_flutter_location_data() -> None:
    assert CHINA_PROVINCE_CITY_MAP == _parse_flutter_locations()


def test_normalize_location_city_accepts_valid_province_city_values() -> None:
    assert normalize_location_city("广东省-深圳市") == "广东省-深圳市"
    assert normalize_location_city("北京市-北京市") == "北京市-北京市"


def test_normalize_location_city_accepts_legacy_city_and_display_values() -> None:
    assert normalize_location_city("深圳市") == "广东省-深圳市"
    assert normalize_location_city("深圳") == "广东省-深圳市"
    assert normalize_location_city("北京市") == "北京市-北京市"
    assert normalize_location_city("北京") == "北京市-北京市"


def test_normalize_location_city_rejects_invalid_values() -> None:
    assert normalize_location_city("啦啦啦") is None
    assert normalize_location_city("广东省-啦啦啦") is None
    assert normalize_location_city("广东省/深圳市") is None
    assert normalize_location_city("") is None
    assert normalize_location_city(None) is None


def test_profile_update_apis_use_shared_location_validation() -> None:
    app_user_api = (BACKEND_ROOT / "app/api/v1/app/user.py").read_text(encoding="utf-8")
    admin_user_api = (BACKEND_ROOT / "app/api/v1/app_users/app_users.py").read_text(encoding="utf-8")

    for source in (app_user_api, admin_user_api):
        assert "normalize_location_city" in source
        assert "所在地不合法" in source


def test_location_city_normalization_migration_exists() -> None:
    migration = BACKEND_ROOT / "migrations/models/55_20260513_normalize_app_user_location_city.py"
    migration_text = migration.read_text(encoding="utf-8")

    assert "UPDATE `app_user`" in migration_text
    assert "`location_city`" in migration_text
    assert "CASE" in migration_text
    assert "'广东省-深圳市'" in migration_text
    assert "'北京市-北京市'" in migration_text
    assert "ELSE NULL" in migration_text
