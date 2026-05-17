import inspect
from pathlib import Path

from app.api.v1.app import moment as app_moment
from app.models.moments import Moment
from app.services import recommended_user_cache

BACKEND_ROOT = Path(__file__).resolve().parents[1]
APP_MOMENT_API = BACKEND_ROOT / "app/api/v1/app/moment.py"
MOMENT_MODEL = BACKEND_ROOT / "app/models/moments.py"
MIGRATION_DIR = BACKEND_ROOT / "migrations/models"


def test_moment_model_has_operation_fields() -> None:
    assert "is_pinned" in Moment._meta.fields_map
    assert "pinned_at" in Moment._meta.fields_map
    assert "recommend_override" in Moment._meta.fields_map


def test_app_moment_feed_accepts_categories_without_certification_filter() -> None:
    source = inspect.getsource(app_moment.get_moment_feed)

    assert "category: str" in source
    assert "recommend" in source
    assert "latest" in source
    assert "following" in source
    assert "UserFollow" in source
    assert "is_anchor=True" not in source
    assert "certified_user_ids" not in source


def test_app_moment_feed_filters_blocked_authors_before_pagination() -> None:
    source = inspect.getsource(app_moment.get_moment_feed)

    assert "exclude_blocked_user_ids" in inspect.getsource(app_moment)
    assert "blocked_user_ids = await exclude_blocked_user_ids" in source
    assert "query = Moment.filter(q)" in source
    assert "query = query.exclude(user_id__in=blocked_user_ids)" in source
    assert "total = await query.count()" in source
    assert "await query.order_by" in source


def test_app_moment_feed_recommend_rule_allows_single_moment_override() -> None:
    moment_source = inspect.getsource(app_moment)
    feed_source = inspect.getsource(app_moment.get_moment_feed)
    cache_source = inspect.getsource(recommended_user_cache)

    assert "recommend_override=True" in moment_source
    assert "get_recommended_user_ids" in feed_source
    assert "is_recommended=True" in cache_source
    assert "RECOMMENDED_USER_IDS_CACHE_TTL_SECONDS" in cache_source
    assert "recommend_override__isnull=True" in moment_source
    assert "recommended_user_ids" in moment_source


def test_app_moment_feed_uses_pinned_then_latest_order() -> None:
    source = inspect.getsource(app_moment.get_moment_feed)

    assert 'order_by("-is_pinned", "-pinned_at", "-created_at", "-id")' in source


def test_app_moment_serializer_returns_operation_flags() -> None:
    source = inspect.getsource(app_moment._serialize_moment)

    for key in [
        "is_pinned",
        "pinned_at",
        "is_recommended",
        "recommend_override",
        "author_is_certified_user",
        "author_is_recommended",
    ]:
        assert key in source
    assert "is_anchor" not in source


def test_moment_operation_migration_adds_fields() -> None:
    migration_text = "\n".join(
        path.read_text(encoding="utf-8") for path in MIGRATION_DIR.glob("*_moment_operation_fields.py")
    )

    assert "is_pinned" in migration_text
    assert "pinned_at" in migration_text
    assert "recommend_override" in migration_text
    assert "idx_moments_feed_order" in migration_text
