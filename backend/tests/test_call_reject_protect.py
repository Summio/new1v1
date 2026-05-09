import importlib.util
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "app" / "core" / "call_reject_protect.py"
SPEC = importlib.util.spec_from_file_location("call_reject_protect_under_test", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load call_reject_protect module for test")
_MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(_MODULE)

calc_left_seconds = _MODULE.calc_left_seconds
should_block_rejected_call = _MODULE.should_block_rejected_call


class CallRejectProtectTests(unittest.TestCase):
    def test_should_not_block_when_left_seconds_is_zero(self) -> None:
        now = datetime(2026, 4, 17, 10, 0, 0, tzinfo=timezone.utc)
        event_time = now - timedelta(seconds=5)

        left = calc_left_seconds(event_time, protect_seconds=5, now=now)
        self.assertEqual(left, 0)
        self.assertFalse(should_block_rejected_call(event_time, protect_seconds=5, now=now))

    def test_should_block_when_left_seconds_is_positive(self) -> None:
        now = datetime(2026, 4, 17, 10, 0, 0, tzinfo=timezone.utc)
        event_time = now - timedelta(seconds=4, milliseconds=100)

        left = calc_left_seconds(event_time, protect_seconds=5, now=now)
        self.assertEqual(left, 1)
        self.assertTrue(should_block_rejected_call(event_time, protect_seconds=5, now=now))
