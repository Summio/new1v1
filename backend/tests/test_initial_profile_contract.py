from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent


def _read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def test_initial_profile_backend_routes_are_registered() -> None:
    app_router_text = _read("app/api/v1/app/__init__.py")
    system_router_text = _read("app/api/v1/apis/system/__init__.py")

    assert "initial_profile_router" in app_router_text
    assert 'prefix="/register/initial-profile"' in app_router_text
    assert "initial_profile_router" in system_router_text
    assert 'prefix="/initial-profile"' in system_router_text
    assert '"/apis/system"' in _read("app/api/v1/__init__.py")


def test_register_no_longer_requires_gender_and_user_info_exposes_completion_flag() -> None:
    register_text = _read("app/api/v1/app/register.py")
    user_text = _read("app/api/v1/app/user.py")
    schema_text = _read("app/schemas/app_user.py")

    assert "gender" not in register_text
    assert "initial_profile_completed" in register_text
    assert "initial_profile_completed" in user_text
    assert "initial_profile_completed" in schema_text
    assert "AppRegisterIn" in schema_text


def test_initial_profile_storage_uses_system_config_and_migration_exists() -> None:
    service_text = _read("app/services/initial_profile_service.py")
    migration_dir = ROOT / "migrations" / "models"
    migration_text = "\n".join(path.read_text(encoding="utf-8") for path in migration_dir.glob("*.py"))

    assert "register_avatar_pool" in service_text
    assert "register_nickname_pool" in service_text
    assert "initial_profile_completed" in migration_text
    assert "app_user" in migration_text


def test_initial_profile_menu_and_admin_page_are_present() -> None:
    init_app_text = _read("app/core/init_app.py")
    api_text = (REPO / "backend/web/src/api/system.js").read_text(encoding="utf-8")
    register_page_text = (REPO / "huanxi/lib/modules/auth/register_page.dart").read_text(encoding="utf-8")
    router_text = (REPO / "huanxi/lib/app/routes/app_router.dart").read_text(encoding="utf-8")
    api_endpoints_text = (REPO / "huanxi/lib/core/constants/api_endpoints.dart").read_text(encoding="utf-8")
    admin_view_path = REPO / "backend/web/src/views/system/initial-profile/index.vue"

    assert "初始资料管理" in init_app_text
    assert "path='initial-profile'" in init_app_text or 'path="initial-profile"' in init_app_text
    assert (
        "component='/system/initial-profile'" in init_app_text or 'component="/system/initial-profile"' in init_app_text
    )
    assert "getInitialProfileConfig" in api_text
    assert "updateInitialProfileAvatarPool" in api_text
    assert "updateInitialProfileNicknamePool" in api_text
    assert admin_view_path.exists()
    assert "InitialProfilePage" in router_text
    assert "initialProfile" in api_endpoints_text
    assert "DropdownButtonFormField" not in register_page_text


def test_initial_profile_nickname_import_accepts_common_leading_labels() -> None:
    from app.services.initial_profile_service import parse_nickname_import_content

    assert parse_nickname_import_content("输入昵称前缀初遇、南山、北屿、清禾、知夏") == [
        "初遇",
        "南山",
        "北屿",
        "清禾",
        "知夏",
    ]


def test_initial_profile_options_contract_excludes_pool_statistics() -> None:
    from app.schemas.initial_profile import InitialProfileOptionsOut
    from app.services.initial_profile_service import build_initial_profile_options

    options = build_initial_profile_options(
        {"male": ["avatar-a.png", "avatar-b.png"], "female": []},
        {
            "male": {"prefixes": ["初遇", "南山"], "suffixes": ["晴天"]},
            "female": {"prefixes": [], "suffixes": []},
        },
        "male",
    )
    payload = InitialProfileOptionsOut(**options).model_dump()

    assert payload["gender"] == "male"
    assert payload["selected_avatar"]
    assert payload["selected_nickname"]
    for field in (
        "avatars",
        "nickname_candidates",
        "avatar_count",
        "nickname_prefix_count",
        "nickname_suffix_count",
        "nickname_combo_count",
    ):
        assert field not in options
        assert field not in payload


def test_flutter_initial_profile_page_no_longer_displays_pool_statistics() -> None:
    page_text = (REPO / "huanxi/lib/modules/auth/initial_profile_page.dart").read_text(encoding="utf-8")

    for removed_text in ("头像数量", "前缀/后缀", "可组合昵称", "_statRow"):
        assert removed_text not in page_text
    assert "'进入'" in page_text
    assert "'退出登录'" in page_text
