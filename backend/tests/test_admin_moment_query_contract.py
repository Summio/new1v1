import inspect

from app.api.v1.moments.moments import _serialize_moment, list_moment


def test_admin_moment_list_uses_prefetched_media() -> None:
    serializer_source = inspect.getsource(_serialize_moment)
    list_source = inspect.getsource(list_moment)

    assert "media_by_moment" in serializer_source
    assert "MomentMedia.filter(moment_id=moment.id)" not in serializer_source
    assert "moment_id__in" in list_source
