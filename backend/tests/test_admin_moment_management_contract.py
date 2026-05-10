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
    assert "/moment/pin" in paths
    assert "/moment/unpin" in paths
    assert "/moment/recommend" in paths
    assert "/moment/unrecommend" in paths
    assert "/moment/clear-recommend-override" in paths


def test_startup_grants_moment_operation_permissions_to_roles() -> None:
    text = Path("app/core/init_app.py").read_text(encoding="utf-8")
    assert '"/api/v1/moment/list"' in text
    assert '"/api/v1/moment/delete"' in text
    assert '"/api/v1/moment/pin"' in text
    assert '"/api/v1/moment/unpin"' in text
    assert '"/api/v1/moment/recommend"' in text
    assert '"/api/v1/moment/unrecommend"' in text
    assert '"/api/v1/moment/clear-recommend-override"' in text


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
    assert "moment_id__in" in text
    assert "AppUser.filter" in text
    assert "recommend_status: str" in text
    assert "pin_status: str" in text


def test_admin_moment_delete_removes_media_before_moment() -> None:
    text = ADMIN_MOMENT_API.read_text(encoding="utf-8")
    assert "async def delete_moment" in text
    assert "MomentMedia.filter(moment_id=moment_id).delete()" in text
    assert "await moment.delete()" in text


def test_admin_moment_missing_uses_business_error_not_http_404() -> None:
    text = ADMIN_MOMENT_API.read_text(encoding="utf-8")
    assert "def _moment_missing" in text
    assert "动态不存在，请刷新后重试" in text
    assert "Fail(code=404" not in text


def test_admin_web_has_moment_page_api_and_user_entry() -> None:
    api_text = WEB_API.read_text(encoding="utf-8")
    moment_view_text = MOMENT_VIEW.read_text(encoding="utf-8")

    assert "getMomentList" in api_text
    assert "deleteMoment" in api_text
    assert "pinMoment" in api_text
    assert "unpinMoment" in api_text
    assert "recommendMoment" in api_text
    assert "unrecommendMoment" in api_text
    assert "clearMomentRecommendOverride" in api_text
    assert "/moment/list" in api_text
    assert "/moment/delete" in api_text
    assert "/moment/pin" in api_text
    assert "/moment/unpin" in api_text
    assert "/moment/recommend" in api_text
    assert "/moment/unrecommend" in api_text
    assert "/moment/clear-recommend-override" in api_text
    assert "api.getMomentList" in moment_view_text
    assert "api.deleteMoment" in moment_view_text
    assert "api.pinMoment" in moment_view_text
    assert "api.unpinMoment" in moment_view_text
    assert "api.recommendMoment" in moment_view_text
    assert "api.unrecommendMoment" in moment_view_text
    assert "api.clearMomentRecommendOverride" in moment_view_text
    assert "推荐认证用户默认推荐" in moment_view_text
    assert "单条推荐" in moment_view_text
    assert "单条取消推荐" in moment_view_text
    assert "恢复默认" in moment_view_text


def test_admin_moment_serializer_returns_operation_state() -> None:
    text = ADMIN_MOMENT_API.read_text(encoding="utf-8")
    for key in [
        "is_pinned",
        "pinned_at",
        "recommend_override",
        "is_recommended",
        "recommend_status_label",
        "author_is_certified_user",
        "author_is_recommended",
    ]:
        assert key in text
    assert "is_anchor" not in text
