from datetime import datetime

import pytest

from app.services.flirt_greet_service import (
    FLIRT_GREET_COOLDOWN_SECONDS,
    build_greet_daily_key,
    build_greet_quota_payload,
    calculate_greet_daily_ttl,
)


def test_greet_daily_key_uses_beijing_calendar_day() -> None:
    now = datetime(2026, 5, 14, 23, 59, 1)

    assert build_greet_daily_key(100019, now=now) == "flirt:greet:daily:20260514:100019"


def test_greet_daily_ttl_expires_at_next_beijing_midnight() -> None:
    now = datetime(2026, 5, 14, 23, 59, 50)

    assert calculate_greet_daily_ttl(now=now) == 10


def test_greet_quota_payload_clamps_remaining_and_reports_cooldown() -> None:
    payload = build_greet_quota_payload(daily_limit=3, used=4, cooldown_seconds=FLIRT_GREET_COOLDOWN_SECONDS)

    assert payload == {
        "daily_limit": 3,
        "used": 4,
        "remaining": 0,
        "enabled": True,
        "cooldown_seconds": 10,
    }


def test_greet_quota_payload_disables_zero_limit() -> None:
    payload = build_greet_quota_payload(daily_limit=0, used=0, cooldown_seconds=0)

    assert payload == {
        "daily_limit": 0,
        "used": 0,
        "remaining": 0,
        "enabled": False,
        "cooldown_seconds": 0,
    }
