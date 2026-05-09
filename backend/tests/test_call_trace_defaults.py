import asyncio
import sys
import unittest
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.services.call_trace_service import CallTraceService  # noqa: E402


class CallTraceDefaultsTests(unittest.TestCase):
    def test_default_enabled_getter_returns_true_when_config_missing(self) -> None:
        service = CallTraceService()

        async def fake_get_im_config() -> dict:
            return {"im_call_trace_enabled": ""}

        service._get_im_config = fake_get_im_config
        self.assertTrue(asyncio.run(service._default_enabled_getter()))

    def test_default_enabled_getter_returns_false_when_config_zero(self) -> None:
        service = CallTraceService()

        async def fake_get_im_config() -> dict:
            return {"im_call_trace_enabled": "0"}

        service._get_im_config = fake_get_im_config
        self.assertFalse(asyncio.run(service._default_enabled_getter()))
