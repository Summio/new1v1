from decimal import Decimal
from pathlib import Path
from types import SimpleNamespace

from app.schemas.app_api import DndSettingsIn
from app.services.ranking_service import BOARD_CHARM, build_app_ranking_rows

BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent
APP_USER_MODEL = BACKEND_ROOT / "app" / "models" / "app_user.py"
APP_USER_SCHEMA = BACKEND_ROOT / "app" / "schemas" / "app_user.py"
APP_API_SCHEMA = BACKEND_ROOT / "app" / "schemas" / "app_api.py"
APP_USER_API = BACKEND_ROOT / "app" / "api" / "v1" / "app" / "user.py"
APP_ROUTERS = BACKEND_ROOT / "app" / "api" / "v1" / "app" / "__init__.py"
CALL_API = BACKEND_ROOT / "app" / "api" / "v1" / "app" / "call.py"
IM_API = BACKEND_ROOT / "app" / "api" / "v1" / "app" / "im.py"
RANKING_SCHEMA = BACKEND_ROOT / "app" / "schemas" / "ranking.py"
MIGRATIONS_DIR = BACKEND_ROOT / "migrations" / "models"
API_ENDPOINTS = REPO_ROOT / "huanxi" / "lib" / "core" / "constants" / "api_endpoints.dart"
AUTH_PROVIDER = REPO_ROOT / "huanxi" / "lib" / "app" / "providers" / "auth_provider.dart"
APP_ROUTER = REPO_ROOT / "huanxi" / "lib" / "app" / "routes" / "app_router.dart"
PROFILE_PAGE = REPO_ROOT / "huanxi" / "lib" / "modules" / "home" / "profile_page.dart"
SETTINGS_PAGE = REPO_ROOT / "huanxi" / "lib" / "modules" / "settings" / "settings_page.dart"
DND_PAGE = REPO_ROOT / "huanxi" / "lib" / "modules" / "profile" / "do_not_disturb_page.dart"
DISCOVER_PAGE = REPO_ROOT / "huanxi" / "lib" / "modules" / "home" / "discover_page.dart"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_dnd_schema_defaults_are_disabled() -> None:
    settings = DndSettingsIn()

    assert settings.text_dnd_enabled is False
    assert settings.video_dnd_enabled is False
    assert settings.ranking_invisible_enabled is False


def test_app_user_model_schema_and_migration_include_dnd_fields() -> None:
    model = _read(APP_USER_MODEL)
    schema = _read(APP_USER_SCHEMA)
    app_api_schema = _read(APP_API_SCHEMA)
    migrations = "\n".join(path.read_text(encoding="utf-8") for path in MIGRATIONS_DIR.glob("*.py"))

    for field in ("text_dnd_enabled", "video_dnd_enabled", "ranking_invisible_enabled"):
        assert field in model
        assert field in schema
        assert field in app_api_schema
        assert field in migrations
    assert "DndSettingsIn" in app_api_schema
    assert "DndSettingsOut" in app_api_schema
    assert "DEFAULT 0" in migrations or "DEFAULT FALSE" in migrations


def test_dnd_settings_routes_are_registered_and_update_current_user_only() -> None:
    user_api = _read(APP_USER_API)
    routers = _read(APP_ROUTERS)

    assert '@router.get("/user/dnd-settings"' in user_api
    assert '@router.put("/user/dnd-settings"' in user_api
    assert "DndSettingsIn" in user_api
    assert "CTX_APP_USER_OBJ.get()" in user_api
    assert "text_dnd_enabled" in user_api
    assert "video_dnd_enabled" in user_api
    assert "ranking_invisible_enabled" in user_api
    assert "user_router" in routers


def test_video_dnd_blocks_dialing_before_call_record_creation_and_push() -> None:
    source = _read(CALL_API)
    dialing_source = source.split("async def dialing(req_in: DialingIn):", 1)[1].split(
        '@router.post("/call/accept"',
        1,
    )[0]
    dnd_branch = dialing_source.split("CallRecord.create", 1)[0]

    assert "video_dnd_enabled" in dnd_branch
    assert 'return Fail(code=403, msg="对方已开启视频勿扰")' in dnd_branch
    assert "_ws_push_call_incoming" not in dnd_branch


def test_text_dnd_blocks_im_text_charge_but_allows_customer_service_sender() -> None:
    source = _read(IM_API)
    charge_source = source.split("async def charge_text_message", 1)[1]

    assert "text_dnd_enabled" in charge_source
    assert "load_customer_service_config" in charge_source
    assert "customer_service.user_id" in charge_source
    assert 'return Fail(code=403, msg="对方已开启文字勿扰")' in charge_source
    assert charge_source.index("text_dnd_enabled") < charge_source.index("charge_im_text_message")


def test_app_ranking_rows_anonymize_invisible_users_without_real_user_id() -> None:
    rows = [
        {
            "rank": 1,
            "user_id": 10,
            "nickname": "第一名",
            "avatar": "/a.png",
            "score": Decimal("100.00"),
            "ranking_invisible_enabled": True,
        },
        {
            "rank": 2,
            "user_id": 11,
            "nickname": "第二名",
            "avatar": "/b.png",
            "score": Decimal("80.00"),
            "ranking_invisible_enabled": False,
        },
    ]

    app_rows = build_app_ranking_rows(rows, board=BOARD_CHARM)

    assert app_rows[0]["user_id"] is None
    assert app_rows[0]["nickname"] == "神秘人"
    assert app_rows[0]["avatar"] == ""
    assert app_rows[0]["is_anonymous"] is True
    assert app_rows[0]["score_gap_text"] == "距榜首 0 钻石"
    assert app_rows[1]["user_id"] == 11
    assert app_rows[1]["is_anonymous"] is False


def test_ranking_schema_allows_anonymous_app_items() -> None:
    schema = _read(RANKING_SCHEMA)

    assert "user_id: int | None" in schema
    assert "is_anonymous: bool = False" in schema


def test_flutter_dnd_entry_page_and_api_contracts_exist() -> None:
    endpoints = _read(API_ENDPOINTS)
    auth_provider = _read(AUTH_PROVIDER)
    app_router = _read(APP_ROUTER)
    profile_page = _read(PROFILE_PAGE)
    settings_page = _read(SETTINGS_PAGE)
    dnd_page = _read(DND_PAGE)

    assert "doNotDisturbSettings" in endpoints
    assert "textDndEnabled" in auth_provider
    assert "videoDndEnabled" in auth_provider
    assert "rankingInvisibleEnabled" in auth_provider
    assert "doNotDisturb" in app_router
    assert "DoNotDisturbPage" in app_router
    assert "勿扰模式" in profile_page
    assert "DoNotDisturbPage" in dnd_page
    assert "文字勿扰" in dnd_page
    assert "开启后不接收文字消息，客服消息除外" in dnd_page
    assert "视频勿扰" in dnd_page
    assert "开启后不接受视频通话" in dnd_page
    assert "榜单隐身" in dnd_page
    assert "开启后在排行榜显示为神秘人" in dnd_page
    assert "previous" in dnd_page
    assert "rollback" in dnd_page
    assert "免打扰模式" not in settings_page


def test_flutter_ranking_anonymous_items_do_not_show_id_or_navigate() -> None:
    discover = _read(DISCOVER_PAGE)

    assert "item.isAnonymous" in discover
    assert "item.userId == null" in discover
    assert "onTap: canOpenProfile" in discover
    assert "神秘人" in discover
