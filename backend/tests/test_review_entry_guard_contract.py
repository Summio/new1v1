import inspect
from pathlib import Path

from app.api.v1.app import review_entry
from app.services import review_entry_guard_service

BACKEND_ROOT = Path(__file__).resolve().parents[1]
APP_INIT = BACKEND_ROOT / "app/api/v1/app/__init__.py"
APP_USER_API = BACKEND_ROOT / "app/api/v1/app/user.py"
APP_MOMENT_API = BACKEND_ROOT / "app/api/v1/app/moment.py"


def test_review_entry_status_route_is_registered() -> None:
    routes = {getattr(route, "path", "") for route in review_entry.router.routes}
    init_text = APP_INIT.read_text(encoding="utf-8")

    assert "/review/entry-status" in routes
    assert "review_entry_router" in init_text


def test_review_entry_status_payload_contains_stable_codes_and_messages() -> None:
    source = inspect.getsource(review_entry_guard_service.build_review_entry_status)

    assert '"profile_edit"' in source
    assert '"moment_publish"' in source
    assert '"profile_review_pending"' in source
    assert '"moment_review_pending"' in source
    assert "您有资料编辑申请待审核，请审核完成后再提交" in inspect.getsource(review_entry_guard_service)
    assert "您有动态待审核，请审核完成后再提交" in inspect.getsource(review_entry_guard_service)


def test_review_entry_guard_service_owns_pending_queries() -> None:
    source = inspect.getsource(review_entry_guard_service)

    assert 'status__in=["pending", "reviewing"]' in source
    assert 'review_status="pending"' in source
    assert "AppUserProfileReviewApply.filter" in source
    assert "Moment.filter" in source


def test_submit_endpoints_reuse_review_entry_guard_service() -> None:
    user_source = APP_USER_API.read_text(encoding="utf-8")
    moment_source = APP_MOMENT_API.read_text(encoding="utf-8")

    assert "has_pending_profile_review" in user_source
    assert "PROFILE_REVIEW_PENDING_MESSAGE" in user_source
    assert "has_pending_moment_review" in moment_source
    assert "MOMENT_REVIEW_PENDING_MESSAGE" in moment_source
