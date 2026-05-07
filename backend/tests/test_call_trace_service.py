import asyncio
import importlib.util
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

if "loguru" not in sys.modules:
    sys.modules["loguru"] = SimpleNamespace(
        logger=SimpleNamespace(
            warning=lambda *args, **kwargs: None,
            error=lambda *args, **kwargs: None,
            info=lambda *args, **kwargs: None,
            remove=lambda *args, **kwargs: None,
            add=lambda *args, **kwargs: None,
        )
    )

MODULE_PATH = Path(__file__).resolve().parents[1] / "app" / "services" / "call_trace_service.py"
SPEC = importlib.util.spec_from_file_location("call_trace_service_under_test", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load call_trace_service module for test")
_MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(_MODULE)

CALL_TRACE_PROTOCOL = _MODULE.CALL_TRACE_PROTOCOL
VALID_CALL_TRACE_PHASES = _MODULE.VALID_CALL_TRACE_PHASES
CallTraceService = _MODULE.CallTraceService
build_call_trace_event = _MODULE.build_call_trace_event
make_call_trace_dedupe_key = _MODULE.make_call_trace_dedupe_key


def _make_call_record() -> SimpleNamespace:
    return SimpleNamespace(
        id=101,
        caller_id=1001,
        callee_id=2002,
        duration=35,
        total_fee=120,
        income_anchor_user_id=2002,
        anchor_income_diamonds=60,
        end_reason=None,
    )


class CallTraceServiceTests(unittest.TestCase):
    def test_make_call_trace_dedupe_key_is_stable(self) -> None:
        self.assertEqual(
            make_call_trace_dedupe_key(call_id=101, phase="dialing"),
            "call:trace:101:dialing",
        )

    def test_build_call_trace_event_contains_protocol_fields(self) -> None:
        event = build_call_trace_event(
            call_record=_make_call_record(),
            phase="dialing",
            actor_user_id=1001,
            reason=None,
            ts=1_720_000_000,
        )
        self.assertEqual(event["protocol"], CALL_TRACE_PROTOCOL)
        self.assertEqual(event["event_id"], "call:trace:101:dialing")
        self.assertEqual(event["call_id"], 101)
        self.assertEqual(event["phase"], "dialing")
        self.assertEqual(event["actor_user_id"], 1001)
        self.assertEqual(event["peer_user_id"], 2002)
        self.assertEqual(event["ts"], 1_720_000_000)
        self.assertEqual(event["duration_seconds"], 35)
        self.assertEqual(event["total_fee_coins"], 120.0)
        self.assertEqual(event["income_anchor_user_id"], 2002)
        self.assertEqual(event["anchor_income_diamonds"], 60.0)
        self.assertIsNone(event["reason"])

    def test_valid_call_trace_phases_cover_required_phases(self) -> None:
        self.assertEqual(
            VALID_CALL_TRACE_PHASES,
            {
                "dialing",
                "accepted",
                "rejected",
                "cancelled",
                "ended",
                "timeout",
                "balance_empty",
                "force_exit",
            },
        )

    def test_append_is_idempotent_for_same_call_id_and_phase(self) -> None:
        sent_events = []
        seen_keys = set()

        async def enabled_getter() -> bool:
            return True

        async def idempotency_claimer(key: str) -> bool:
            if key in seen_keys:
                return False
            seen_keys.add(key)
            return True

        async def message_sender(*, from_user_id: int, to_user_id: int, event: dict) -> bool:
            sent_events.append((from_user_id, to_user_id, event["phase"]))
            return True

        service = CallTraceService(
            enabled_getter=enabled_getter,
            idempotency_claimer=idempotency_claimer,
            message_sender=message_sender,
        )
        record = _make_call_record()

        self.assertTrue(asyncio.run(service.append(record, phase="dialing")))
        self.assertFalse(asyncio.run(service.append(record, phase="dialing")))
        self.assertEqual(sent_events, [(1001, 2002, "dialing")])

    def test_append_returns_false_when_feature_disabled(self) -> None:
        sent_events = []

        async def enabled_getter() -> bool:
            return False

        async def idempotency_claimer(_key: str) -> bool:
            return True

        async def message_sender(*, from_user_id: int, to_user_id: int, event: dict) -> bool:
            sent_events.append((from_user_id, to_user_id, event["phase"]))
            return True

        service = CallTraceService(
            enabled_getter=enabled_getter,
            idempotency_claimer=idempotency_claimer,
            message_sender=message_sender,
        )

        self.assertFalse(asyncio.run(service.append(_make_call_record(), phase="accepted")))
        self.assertEqual(sent_events, [])

    def test_append_swallows_sender_error(self) -> None:
        async def enabled_getter() -> bool:
            return True

        async def idempotency_claimer(_key: str) -> bool:
            return True

        async def message_sender(*, from_user_id: int, to_user_id: int, event: dict) -> bool:
            raise RuntimeError("sender boom")

        service = CallTraceService(
            enabled_getter=enabled_getter,
            idempotency_claimer=idempotency_claimer,
            message_sender=message_sender,
        )

        self.assertFalse(asyncio.run(service.append(_make_call_record(), phase="accepted")))
