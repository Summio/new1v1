from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_ROOT = REPO_ROOT / "backend"

CERTIFIED_USER_API = BACKEND_ROOT / "app/api/v1/app/certified_user.py"
APP_USER_MODEL = BACKEND_ROOT / "app/models/app_user.py"
APP_USER_SCHEMA = BACKEND_ROOT / "app/schemas/app_user.py"
APP_USER_ADMIN_API = BACKEND_ROOT / "app/api/v1/app_users/app_users.py"
PRESENCE = BACKEND_ROOT / "app/websocket/presence.py"
WS_MANAGER = BACKEND_ROOT / "app/websocket/manager.py"
SETTINGS_CONFIG = BACKEND_ROOT / "app/settings/config.py"
ADMIN_MODEL = BACKEND_ROOT / "app/models/admin.py"
GIFT_SCHEMA = BACKEND_ROOT / "app/schemas/gift.py"
SEED_TEST_DATA_SCRIPT = BACKEND_ROOT / "scripts/seed_test_data.py"
LEGACY_AVATAR_SCRIPT = BACKEND_ROOT / "scripts/update_anchor_avatars.py"
GITIGNORE = REPO_ROOT / ".gitignore"
APP_USER_VIEW = BACKEND_ROOT / "web/src/views/operation/app-user/index.vue"
MOMENT_VIEW = BACKEND_ROOT / "web/src/views/operation/moment/index.vue"
WEB_API_INDEX = BACKEND_ROOT / "web/src/api/index.js"
CERTIFIED_USER_PROVIDER = REPO_ROOT / "huanxi/lib/app/providers/certified_user_provider.dart"
HOME_PAGE = REPO_ROOT / "huanxi/lib/modules/home/home_page.dart"


def test_certified_user_model_has_recommend_fields() -> None:
    text = APP_USER_MODEL.read_text(encoding="utf-8")

    assert "is_recommended" in text
    assert "recommend_weight" in text


def test_certified_user_list_supports_online_section_sorting() -> None:
    text = CERTIFIED_USER_API.read_text(encoding="utf-8")

    assert "section: str" in text
    assert 'filters["id__in"]' not in text
    assert "users = await q.all()" not in text
    assert "_fetch_sorted_certified_user_page" in text
    assert "online_ids" in text
    assert "user_id not in online_ids" in text
    assert "is_recommended" in text
    assert "True" in text
    assert "recommend_weight" in text
    assert "certification_reviewed_at" in text
    assert "get_online_user_id_page" in text
    assert "count_online_user_ids" in text
    assert "filter_online_user_ids" in text
    assert "_availability_sort_rank" in text
    assert "video_dnd_enabled" in text


def test_presence_records_online_since_for_active_sorting() -> None:
    presence_text = PRESENCE.read_text(encoding="utf-8")
    manager_text = WS_MANAGER.read_text(encoding="utf-8")

    assert "ws:online_since" in presence_text
    assert "ws:online_certified_user_since" in presence_text
    assert "ws:online_anchor_since" in presence_text
    assert "mark_online_since" in presence_text
    assert "clear_online_since" in presence_text
    assert "get_online_since_map" in presence_text
    assert "manual_offline_keys" in presence_text
    assert "mark_online_since" in manager_text
    assert "clear_online_since" in manager_text


def test_legacy_online_anchor_key_kept_only_as_compatibility_alias() -> None:
    text = PRESENCE.read_text(encoding="utf-8")

    assert "_WS_ONLINE_CERTIFIED_USER_SINCE_KEY" in text
    assert "_WS_ONLINE_ANCHOR_SINCE_KEY" in text
    assert "legacy" in text.lower()
    assert "zunionstore" in text


def test_redis_connection_settings_are_environment_driven() -> None:
    text = SETTINGS_CONFIG.read_text(encoding="utf-8")

    assert 'REDIS_HOST: str = os.getenv("REDIS_HOST", "localhost")' in text
    assert 'REDIS_PORT: int = int(os.getenv("REDIS_PORT", "6379"))' in text
    assert 'REDIS_DB: int = int(os.getenv("REDIS_DB", "0"))' in text


def test_runtime_call_and_gift_amount_descriptions_use_coin_units() -> None:
    combined = "\n".join(
        [
            ADMIN_MODEL.read_text(encoding="utf-8"),
            GIFT_SCHEMA.read_text(encoding="utf-8"),
        ]
    )

    assert "价格(金币)" in combined
    assert "总费用(金币)" in combined
    assert "已扣费总额(金币)" in combined
    assert "礼物单价(金币)" in combined
    assert "礼物总价(金币)" in combined
    assert "价格(分)" not in combined
    assert "总费用(分)" not in combined
    assert "已扣费总额(分)" not in combined
    assert "礼物单价(分)" not in combined
    assert "礼物总价(分)" not in combined


def test_legacy_seed_and_avatar_scripts_are_deprecated_guards() -> None:
    for path in [SEED_TEST_DATA_SCRIPT, LEGACY_AVATAR_SCRIPT]:
        text = path.read_text(encoding="utf-8")
        assert "已废弃" in text
        assert "SystemExit" in text
        assert "mysql://root:123456@localhost:3306/huanxi" not in text
        assert "AppUser.all().delete()" not in text
        assert "Anchor.all()" not in text
        assert "Anchor.create" not in text
        assert "is_anchor=True" not in text


def test_backend_logs_are_ignored_by_git() -> None:
    text = GITIGNORE.read_text(encoding="utf-8")

    assert "backend/logs/" in text
    assert "backend/app/logs/" in text


def test_admin_update_and_page_support_certified_user_recommend_fields() -> None:
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


def test_admin_app_user_hides_sensitive_certification_fields_from_table_and_query() -> None:
    view_text = APP_USER_VIEW.read_text(encoding="utf-8")

    assert "title: '认证状态'" not in view_text
    assert "title: '认证正面照'" not in view_text
    assert "title: '通话价格'" not in view_text
    assert '<QueryBarItem label="认证状态"' not in view_text
    assert '<NFormItem label="认证状态"' in view_text
    assert '<NFormItem label="认证正面照"' in view_text
    assert '<NFormItem label="通话价格"' in view_text


def test_admin_app_user_filters_call_price_options_by_certification_status() -> None:
    view_text = APP_USER_VIEW.read_text(encoding="utf-8")

    assert "certifiedCallPricePaidOptions" in view_text
    assert "certifiedCallPriceFreeOptions" in view_text
    assert "option.value > 0" in view_text
    assert "请先配置至少一个收费通话价格档位" in view_text
    assert "真人认证用户不能设置免费通话价格" in view_text


def test_admin_app_user_edit_modal_hides_assets_and_moments_tabs() -> None:
    view_text = APP_USER_VIEW.read_text(encoding="utf-8")
    api_text = WEB_API_INDEX.read_text(encoding="utf-8")

    assert 'tab="资产信息"' not in view_text
    assert 'tab="动态"' not in view_text
    assert 'tab="账单"' in view_text
    assert 'tab="通话记录"' in view_text
    assert "handleOpenUserMoments" not in view_text
    assert "moment-entry" not in view_text
    assert "{ title: '金币'" in view_text
    assert "{ title: '钻石'" in view_text
    assert "{ title: '冻结钻石'" in view_text
    assert MOMENT_VIEW.exists()
    assert "getMomentList" in api_text
    assert "deleteMoment" in api_text


def test_flutter_home_tabs_send_certified_user_section() -> None:
    provider_text = CERTIFIED_USER_PROVIDER.read_text(encoding="utf-8")
    home_text = HOME_PAGE.read_text(encoding="utf-8")

    assert "section" in provider_text
    assert "setSection" in provider_text
    assert "'section': requestSection" in provider_text
    assert "_sectionForIndex" in home_text
    assert "setSection(_sectionForIndex(index))" in home_text
