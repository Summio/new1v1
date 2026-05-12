from __future__ import annotations

from collections.abc import Iterable
from types import SimpleNamespace
from typing import Any

from tortoise.expressions import Q

from app.models import AppUser, CallRecord

AVAILABILITY_ONLINE = "online"
AVAILABILITY_BUSY = "busy"
AVAILABILITY_DND = "dnd"
AVAILABILITY_OFFLINE = "offline"

_AVAILABILITY_LABELS = {
    AVAILABILITY_ONLINE: "在线",
    AVAILABILITY_BUSY: "忙碌",
    AVAILABILITY_DND: "勿扰",
    AVAILABILITY_OFFLINE: "离线",
}


def _normalize_user_ids(user_ids: Iterable[int]) -> list[int]:
    ids: list[int] = []
    seen: set[int] = set()
    for raw_id in user_ids:
        try:
            user_id = int(raw_id)
        except (TypeError, ValueError):
            continue
        if user_id <= 0 or user_id in seen:
            continue
        seen.add(user_id)
        ids.append(user_id)
    return ids


def resolve_availability_payload(user: Any, *, is_online: bool, is_busy: bool) -> dict[str, bool | str]:
    """构建用户对外展示的可用状态。"""
    video_dnd_enabled = bool(getattr(user, "video_dnd_enabled", False))
    online = bool(is_online)
    busy = bool(is_busy)

    if not online:
        status = AVAILABILITY_OFFLINE
    elif video_dnd_enabled:
        status = AVAILABILITY_DND
    elif busy:
        status = AVAILABILITY_BUSY
    else:
        status = AVAILABILITY_ONLINE

    return {
        "is_online": online,
        "is_busy": busy,
        "video_dnd_enabled": video_dnd_enabled,
        "availability_status": status,
        "availability_label": _AVAILABILITY_LABELS[status],
    }


async def get_busy_user_ids(user_ids: Iterable[int]) -> set[int]:
    """批量获取处于 pending/ongoing 通话中的用户 ID。"""
    ids = _normalize_user_ids(user_ids)
    if not ids:
        return set()

    rows = await (
        CallRecord.filter(status__in=["pending", "ongoing"])
        .filter(Q(caller_id__in=ids) | Q(callee_id__in=ids))
        .values("caller_id", "callee_id")
    )
    id_set = set(ids)
    busy_ids: set[int] = set()
    for row in rows:
        for field in ("caller_id", "callee_id"):
            try:
                user_id = int(row.get(field) or 0)
            except (TypeError, ValueError):
                continue
            if user_id in id_set:
                busy_ids.add(user_id)
    return busy_ids


async def build_availability_payload_map(
    users: Iterable[Any],
    *,
    online_ids: set[int],
    busy_user_ids: set[int] | None = None,
) -> dict[int, dict[str, bool | str]]:
    user_list = list(users)
    if busy_user_ids is None:
        busy_user_ids = await get_busy_user_ids(int(getattr(user, "id", 0) or 0) for user in user_list)

    payloads: dict[int, dict[str, bool | str]] = {}
    for user in user_list:
        try:
            user_id = int(getattr(user, "id", 0) or 0)
        except (TypeError, ValueError):
            continue
        if user_id <= 0:
            continue
        payloads[user_id] = resolve_availability_payload(
            user,
            is_online=user_id in online_ids,
            is_busy=user_id in busy_user_ids,
        )
    return payloads


async def build_user_availability_event_payload(user_id: int) -> dict[str, bool | int | str]:
    normalized_user_id = int(user_id)
    user = await AppUser.filter(id=normalized_user_id).first()
    if user is None:
        user = SimpleNamespace(id=normalized_user_id, video_dnd_enabled=False)

    from app.websocket.presence import is_online as _is_online_user

    online = await _is_online_user(normalized_user_id)
    payloads = await build_availability_payload_map(
        [user],
        online_ids={normalized_user_id} if online else set(),
    )
    payload = payloads.get(
        normalized_user_id,
        resolve_availability_payload(user, is_online=False, is_busy=False),
    )
    return {
        "user_id": normalized_user_id,
        "online": bool(payload["is_online"]),
        **payload,
    }
