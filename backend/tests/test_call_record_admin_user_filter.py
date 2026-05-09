import inspect

from app.api.v1.call_records.call_records import list_call_record


def test_call_record_list_supports_user_id_query() -> None:
    params = inspect.signature(list_call_record).parameters
    assert "user_id" in params
