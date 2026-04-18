from datetime import datetime, timezone
import math

from app.core.time_utils import to_utc_aware


def calc_left_seconds(
    event_time: datetime | None,
    protect_seconds: int,
    *,
    now: datetime | None = None,
) -> int:
    if event_time is None or protect_seconds <= 0:
        return 0

    current = to_utc_aware(now) if now is not None else datetime.now(timezone.utc)
    elapsed = (current - to_utc_aware(event_time)).total_seconds()
    left = protect_seconds - elapsed
    return max(0, math.ceil(left))


def should_block_rejected_call(
    event_time: datetime | None,
    protect_seconds: int,
    *,
    now: datetime | None = None,
) -> bool:
    return calc_left_seconds(
        event_time=event_time,
        protect_seconds=protect_seconds,
        now=now,
    ) > 0
