from __future__ import annotations

from datetime import datetime, timedelta, timezone

from app.settings.config import settings


def _get_local_zone() -> timezone:
    """统一使用北京时间（Asia/Shanghai）。所有 naive datetime 均解释为北京时间。"""
    tz_name = str(settings.TORTOISE_ORM.get("timezone") or "UTC")
    if tz_name == "Asia/Shanghai":
        return timezone(timedelta(hours=8))
    return timezone.utc


LOCAL_ZONE = _get_local_zone()


def now_utc() -> datetime:
    """返回当前 UTC 时间（aware），用于与 to_utc_aware 保持一致的时区语义。"""
    return datetime.now(timezone.utc)


def now_local_naive() -> datetime:
    """Current local wall-clock time without tzinfo (for DB `use_tz=False`)."""
    return datetime.now(LOCAL_ZONE).replace(tzinfo=None)


def to_utc_aware(dt: datetime | None) -> datetime:
    """Normalize datetime to UTC-aware.

    For naive datetimes from DB (`use_tz=False`), interpret them as local
    project timezone (Asia/Shanghai by default), then convert to UTC.
    """
    if dt is None:
        return datetime.now(timezone.utc)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=LOCAL_ZONE)
    return dt.astimezone(timezone.utc)


def to_local_naive_for_db(dt: datetime) -> datetime:
    """Normalize datetime for DB write when `use_tz=False`.

    - naive datetime: treat as local wall-clock and keep unchanged
    - aware datetime: convert to local timezone then drop tzinfo
    """
    if dt.tzinfo is None:
        return dt
    return dt.astimezone(LOCAL_ZONE).replace(tzinfo=None)
