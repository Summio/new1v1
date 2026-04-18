from datetime import datetime, timezone
import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).resolve().parents[1] / "app" / "core" / "time_utils.py"
SPEC = importlib.util.spec_from_file_location("time_utils_under_test", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load time_utils module for test")
_MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(_MODULE)

to_utc_aware = _MODULE.to_utc_aware
to_local_naive_for_db = _MODULE.to_local_naive_for_db


class TimeUtilsTests(unittest.TestCase):
    def test_to_utc_aware_converts_naive_local_time_to_utc(self) -> None:
        # Project DB stores naive local time (Asia/Shanghai), should convert to UTC.
        naive_local = datetime(2026, 4, 17, 16, 0, 0)
        converted = to_utc_aware(naive_local)
        self.assertEqual(
            converted,
            datetime(2026, 4, 17, 8, 0, 0, tzinfo=timezone.utc),
        )

    def test_to_utc_aware_keeps_utc_time_semantics(self) -> None:
        aware_utc = datetime(2026, 4, 17, 8, 0, 0, tzinfo=timezone.utc)
        converted = to_utc_aware(aware_utc)
        self.assertEqual(converted, aware_utc)

    def test_to_local_naive_for_db_converts_aware_utc_to_local_naive(self) -> None:
        aware_utc = datetime(2026, 4, 17, 9, 0, 0, tzinfo=timezone.utc)
        converted = to_local_naive_for_db(aware_utc)
        self.assertIsNone(converted.tzinfo)
        self.assertEqual(converted, datetime(2026, 4, 17, 17, 0, 0))

    def test_to_local_naive_for_db_keeps_naive_value(self) -> None:
        naive = datetime(2026, 4, 17, 17, 0, 0)
        converted = to_local_naive_for_db(naive)
        self.assertEqual(converted, naive)


if __name__ == "__main__":
    unittest.main()
