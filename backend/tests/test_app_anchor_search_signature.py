import inspect

from app.api.v1.app.anchor import anchor_list


def test_anchor_list_supports_keyword_query() -> None:
    params = inspect.signature(anchor_list).parameters

    assert "keyword" in params


def test_anchor_list_keyword_keeps_gender_filter_available() -> None:
    params = inspect.signature(anchor_list).parameters

    assert "gender" in params

