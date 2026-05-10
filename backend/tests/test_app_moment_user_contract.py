import inspect

from app.api.v1.app.moment import (
    _prefetch_moment_media,
    _serialize_moment,
    get_user_moments,
)


def test_user_moments_endpoint_accepts_user_id() -> None:
    params = inspect.signature(get_user_moments).parameters

    assert "user_id" in params
    assert "page" in params
    assert "page_size" in params


def test_user_moments_filters_by_target_user() -> None:
    source = inspect.getsource(get_user_moments)
    serializer_source = inspect.getsource(_serialize_moment)

    assert 'Moment.filter(user_id=user_id, review_status="approved")' in source
    assert "_serialize_moment" in source
    assert '"media_list"' in serializer_source
    assert '"user"' in serializer_source


def test_app_moment_serialization_uses_prefetched_media() -> None:
    serializer_source = inspect.getsource(_serialize_moment)
    prefetch_source = inspect.getsource(_prefetch_moment_media)
    feed_source = inspect.getsource(__import__("app.api.v1.app.moment", fromlist=["get_moment_feed"]).get_moment_feed)
    user_source = inspect.getsource(get_user_moments)

    assert "media_by_moment" in serializer_source
    assert "MomentMedia.filter(moment_id=moment.id)" not in serializer_source
    assert "moment_id__in" in prefetch_source
    assert "_prefetch_moment_media(moments)" in feed_source
    assert "_prefetch_moment_media(moments)" in user_source
