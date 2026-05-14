from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
TIM_SERVICE = BACKEND_ROOT / "app/services/tim_service.py"


def test_tim_text_send_does_not_retry_invalid_identifier_error() -> None:
    source = TIM_SERVICE.read_text(encoding="utf-8")
    text_send_body = source.split("async def _send_c2c_text_msg", 1)[1]
    text_send_body = text_send_body.split("async def send_text_message", 1)[0]

    assert "_NON_RETRYABLE_TIM_ERROR_CODES" in source
    assert "20003" in source
    assert 'body.get("ErrorCode"' in text_send_body
    assert "in _NON_RETRYABLE_TIM_ERROR_CODES" in text_send_body
    assert "return False" in text_send_body
