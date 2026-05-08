from pathlib import Path

from app.api.v1 import v1_router
from app.core import init_app


ADMIN_MOMENT_API = Path("app/api/v1/moments/moments.py")
WEB_API = Path("../backend/web/src/api/index.js")
APP_USER_VIEW = Path("../backend/web/src/views/operation/app-user/index.vue")
MOMENT_VIEW = Path("../backend/web/src/views/operation/moment/index.vue")


def test_admin_moment_routes_registered() -> None:
    paths = {getattr(route, "path", "") for route in v1_router.routes}
    assert "/moment/list" in paths
    assert "/moment/delete" in paths


def test_operation_menu_blueprint_has_moment_management_menu() -> None:
    children = init_app.build_operation_children(parent_id=100)
    assert any(menu.name == "动态管理" and menu.component == "/operation/moment" for menu in children)


def test_admin_moment_list_supports_user_filter_and_keyword() -> None:
    text = ADMIN_MOMENT_API.read_text(encoding="utf-8")
    assert "async def list_moment" in text
    assert "user_id: str" in text
    assert "target_user_id" in text
    assert "keyword: str" in text
    assert "Moment.filter" in text
    assert "MomentMedia.filter(moment_id=moment.id)" in text
    assert "AppUser.filter" in text


def test_admin_moment_delete_removes_media_before_moment() -> None:
    text = ADMIN_MOMENT_API.read_text(encoding="utf-8")
    assert "async def delete_moment" in text
    assert "MomentMedia.filter(moment_id=moment_id).delete()" in text
    assert "await moment.delete()" in text


def test_admin_web_has_moment_page_api_and_user_entry() -> None:
    api_text = WEB_API.read_text(encoding="utf-8")
    app_user_text = APP_USER_VIEW.read_text(encoding="utf-8")
    moment_view_text = MOMENT_VIEW.read_text(encoding="utf-8")

    assert "getMomentList" in api_text
    assert "deleteMoment" in api_text
    assert "/moment/list" in api_text
    assert "/moment/delete" in api_text
    assert "handleOpenUserMoments" in app_user_text
    assert "/operation/moment" in app_user_text
    assert "api.getMomentList" in moment_view_text
    assert "api.deleteMoment" in moment_view_text
