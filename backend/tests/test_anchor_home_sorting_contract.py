from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_ROOT = REPO_ROOT / "backend"

ANCHOR_API = BACKEND_ROOT / "app/api/v1/app/anchor.py"
APP_USER_MODEL = BACKEND_ROOT / "app/models/app_user.py"
APP_USER_SCHEMA = BACKEND_ROOT / "app/schemas/app_user.py"
APP_USER_ADMIN_API = BACKEND_ROOT / "app/api/v1/app_users/app_users.py"
PRESENCE = BACKEND_ROOT / "app/websocket/presence.py"
WS_MANAGER = BACKEND_ROOT / "app/websocket/manager.py"
APP_USER_VIEW = BACKEND_ROOT / "web/src/views/operation/app-user/index.vue"
ANCHOR_PROVIDER = REPO_ROOT / "huanxi/lib/app/providers/anchor_provider.dart"
HOME_PAGE = REPO_ROOT / "huanxi/lib/modules/home/home_page.dart"


def test_anchor_model_has_recommend_fields() -> None:
    text = APP_USER_MODEL.read_text(encoding="utf-8")

    assert "is_recommended" in text
    assert "recommend_weight" in text


def test_anchor_list_supports_online_section_sorting() -> None:
    text = ANCHOR_API.read_text(encoding="utf-8")

    assert "section: str" in text
    assert 'filters["id__in"]' not in text
    assert "users = await q.all()" not in text
    assert "_fetch_sorted_anchor_page" in text
    assert "online_ids" in text
    assert "user.id in online_ids" in text
    assert "is_recommended" in text
    assert "True" in text
    assert "recommend_weight" in text
    assert "anchor_reviewed_at" in text
    assert "get_online_user_id_page" in text
    assert "count_online_user_ids" in text


def test_presence_records_online_since_for_active_sorting() -> None:
    presence_text = PRESENCE.read_text(encoding="utf-8")
    manager_text = WS_MANAGER.read_text(encoding="utf-8")

    assert "ws:online_since" in presence_text
    assert "mark_online_since" in presence_text
    assert "clear_online_since" in presence_text
    assert "get_online_since_map" in presence_text
    assert "manual_offline_keys" in presence_text
    assert "mark_online_since" in manager_text
    assert "clear_online_since" in manager_text


def test_admin_update_and_page_support_anchor_recommend_fields() -> None:
    schema_text = APP_USER_SCHEMA.read_text(encoding="utf-8")
    api_text = APP_USER_ADMIN_API.read_text(encoding="utf-8")
    view_text = APP_USER_VIEW.read_text(encoding="utf-8")

    assert "is_recommended" in schema_text
    assert "recommend_weight" in schema_text
    assert 'update_data["is_recommended"]' in api_text
    assert 'update_data["recommend_weight"]' in api_text
    assert "首页推荐" in view_text
    assert "modalForm.is_recommended" in view_text
    assert "modalForm.recommend_weight" in view_text


def test_flutter_home_tabs_send_anchor_section() -> None:
    provider_text = ANCHOR_PROVIDER.read_text(encoding="utf-8")
    home_text = HOME_PAGE.read_text(encoding="utf-8")

    assert "section" in provider_text
    assert "setSection" in provider_text
    assert "'section': requestSection" in provider_text
    assert "_sectionForIndex" in home_text
    assert "setSection(_sectionForIndex(index))" in home_text
