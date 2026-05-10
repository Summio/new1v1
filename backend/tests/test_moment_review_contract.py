import inspect
from pathlib import Path

from app.api.v1.app import moment as app_moment
from app.api.v1.moments import moments as admin_moment
from app.models.moments import Moment


BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent
MIGRATION_DIR = BACKEND_ROOT / "migrations/models"
WEB_API = BACKEND_ROOT / "web/src/api/index.js"
WEB_MOMENT_VIEW = BACKEND_ROOT / "web/src/views/operation/moment/index.vue"
INIT_APP = BACKEND_ROOT / "app/core/init_app.py"


def test_moment_model_has_review_fields() -> None:
    for field in ["review_status", "reviewed_at", "reviewed_by", "review_remark"]:
        assert field in Moment._meta.fields_map


def test_moment_review_migration_backfills_existing_moments_as_approved() -> None:
    migration_text = "\n".join(
        path.read_text(encoding="utf-8") for path in MIGRATION_DIR.glob("*_moment_review_fields.py")
    )

    assert "review_status" in migration_text
    assert "DEFAULT 'approved'" in migration_text
    assert "idx_moments_review_status" in migration_text
    assert "idx_moments_user_review_status" in migration_text


def test_app_moment_create_submits_pending_and_blocks_existing_pending() -> None:
    source = inspect.getsource(app_moment.create_moment)

    assert 'review_status="pending"' in source
    assert 'Moment.filter(user_id=app_user.id, review_status="pending").exists()' in source
    assert "您有动态待审核，请审核完成后再提交" in source
    assert '"review_status": moment.review_status or "pending"' in source


def test_app_public_moment_queries_only_return_approved_but_mine_keeps_all() -> None:
    feed_source = inspect.getsource(app_moment.get_moment_feed)
    user_source = inspect.getsource(app_moment.get_user_moments)
    mine_source = inspect.getsource(app_moment.get_my_moments)

    assert 'Q(review_status="approved")' in feed_source
    assert 'review_status="approved"' in user_source
    assert 'review_status="approved"' not in mine_source


def test_app_moment_serializer_returns_review_fields() -> None:
    source = inspect.getsource(app_moment._serialize_moment)

    for key in ["review_status", "reviewed_at", "reviewed_by", "review_remark"]:
        assert key in source


def test_admin_moment_review_endpoint_and_permissions_exist() -> None:
    routes = {getattr(route, "path", "") for route in admin_moment.router.routes}
    admin_source = inspect.getsource(admin_moment)
    init_text = INIT_APP.read_text(encoding="utf-8")

    assert "/review" in routes
    assert "MomentReviewIn" in admin_source
    assert 'review_status: str = Query("all"' in admin_source
    assert '"/api/v1/moment/review"' in init_text


def test_admin_web_moment_review_controls_exist() -> None:
    api_text = WEB_API.read_text(encoding="utf-8")
    view_text = WEB_MOMENT_VIEW.read_text(encoding="utf-8")

    assert "reviewMoment" in api_text
    assert "/moment/review" in api_text
    assert "reviewStatusOptions" in view_text
    assert "审核通过" in view_text
    assert "审核驳回" in view_text
    assert "驳回原因" in view_text
