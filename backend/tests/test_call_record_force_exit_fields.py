from app.models import CallRecord


def test_call_record_has_force_exit_settlement_fields() -> None:
    fields = CallRecord._meta.fields_map
    assert "effective_ended_at" in fields
    assert "end_basis" in fields
    assert "force_exit_user_id" in fields
