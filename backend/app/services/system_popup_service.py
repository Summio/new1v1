from __future__ import annotations

import calendar
from datetime import datetime, time, timedelta
from enum import Enum
from typing import Any

from tortoise.exceptions import IntegrityError
from tortoise.expressions import Q
from tortoise.transactions import in_transaction

from app.core.time_utils import now_local_naive, to_local_naive_for_db
from app.models import AppUser, SystemPopup, SystemPopupReceipt, SystemPopupTask

POPUP_TYPES = {"announcement", "account", "review", "interaction"}
SEND_MODES = {"immediate", "once", "repeat", "app_start"}
TASK_STATUSES = {"draft", "scheduled", "running", "paused", "completed", "cancelled"}
TARGET_MODES = {"all", "user_ids", "filter"}
REPEAT_TYPES = {"daily", "weekly", "monthly"}
TARGET_FILTER_KEYS = {"gender", "is_certified_user"}
STARTUP_POPUP_TASK_SCAN_LIMIT = 5
STARTUP_POPUP_RETURN_LIMIT = 3
PENDING_POPUP_SCAN_LIMIT = 50
PENDING_POPUP_RETURN_LIMIT = 10


class PopupValidationError(ValueError):
    pass


def format_popup_datetime(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.isoformat(timespec="seconds")


def _normalize_schedule_datetime(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return to_local_naive_for_db(value)


def _scalar_value(value: Any, default: str = "") -> str:
    if value is None:
        return default
    if isinstance(value, Enum):
        return str(value.value).strip()
    return str(value).strip()


def normalize_popup_choice(value: Any, choices: set[str], default: str = "") -> str:
    raw_value = _scalar_value(value, default)
    if raw_value in choices:
        return raw_value
    legacy_value = raw_value.rsplit(".", 1)[-1].lower()
    if legacy_value in choices:
        return legacy_value
    return raw_value


def normalize_user_ids(value: list[int | str] | str | None) -> list[int]:
    if value is None or value == "":
        return []
    raw_items: list[int | str]
    if isinstance(value, str):
        raw_items = [item.strip() for item in value.split(",") if item.strip()]
    elif isinstance(value, list):
        raw_items = value
    else:
        raise PopupValidationError("用户ID格式不正确")

    user_ids: set[int] = set()
    for item in raw_items:
        try:
            user_id = int(item)
        except (TypeError, ValueError) as exc:
            raise PopupValidationError("用户ID必须是正整数") from exc
        if user_id <= 0:
            raise PopupValidationError("用户ID必须是正整数")
        user_ids.add(user_id)
    return sorted(user_ids)


def _normalize_target_filters(target_mode: str, raw_filters: dict[str, Any] | None) -> dict[str, Any] | None:
    if target_mode != "filter":
        return None
    filters = raw_filters or {}
    normalized: dict[str, Any] = {}
    for key, value in filters.items():
        if value is None or value == "":
            continue
        if key not in TARGET_FILTER_KEYS:
            raise PopupValidationError("不支持的筛选条件")
        if key == "gender":
            if value not in {"male", "female"}:
                raise PopupValidationError("性别筛选条件不正确")
            normalized[key] = value
        elif key == "is_certified_user":
            normalized[key] = bool(value)
    if not normalized:
        raise PopupValidationError("请至少选择一个筛选条件")
    return normalized


def ensure_repeat_has_end_condition(
    *,
    send_mode: str,
    end_at: datetime | None,
    max_runs: int | None,
) -> None:
    if send_mode == "repeat" and end_at is None and max_runs is None:
        raise PopupValidationError("周期重复必须填写结束时间或最大发送次数")
    if max_runs is not None and max_runs <= 0:
        raise PopupValidationError("最大发送次数必须大于0")


def _parse_repeat_time(value: str | None) -> time:
    if not value:
        raise PopupValidationError("周期重复必须填写发送时间")
    try:
        hour, minute = [int(part) for part in value.split(":", 1)]
    except (ValueError, AttributeError) as exc:
        raise PopupValidationError("发送时间格式必须为 HH:mm") from exc
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        raise PopupValidationError("发送时间格式必须为 HH:mm")
    return time(hour=hour, minute=minute)


def calculate_next_run_at(
    *,
    repeat_type: str,
    after: datetime,
    repeat_time: str,
    repeat_weekday: int | None = None,
    repeat_month_day: int | None = None,
) -> datetime:
    run_time = _parse_repeat_time(repeat_time)
    if repeat_type == "daily":
        candidate = datetime.combine(after.date(), run_time)
        if candidate <= after:
            candidate += timedelta(days=1)
        return candidate
    if repeat_type == "weekly":
        if repeat_weekday is None or repeat_weekday < 0 or repeat_weekday > 6:
            raise PopupValidationError("每周重复必须选择周几")
        days = (repeat_weekday - after.weekday()) % 7
        candidate = datetime.combine((after + timedelta(days=days)).date(), run_time)
        if candidate <= after:
            candidate += timedelta(days=7)
        return candidate
    if repeat_type == "monthly":
        if repeat_month_day is None or repeat_month_day < 1 or repeat_month_day > 31:
            raise PopupValidationError("每月重复必须选择日期")
        year = after.year
        month = after.month
        for _ in range(36):
            last_day = calendar.monthrange(year, month)[1]
            if repeat_month_day <= last_day:
                candidate = datetime(year, month, repeat_month_day, run_time.hour, run_time.minute)
                if candidate > after:
                    return candidate
            month += 1
            if month > 12:
                month = 1
                year += 1
        raise PopupValidationError("无法计算下一次发送时间")
    raise PopupValidationError("周期类型仅支持 daily/weekly/monthly")


def build_popup_run_key(*, task_id: int, scheduled_run_at: datetime) -> str:
    return f"popup_task:{int(task_id)}:{scheduled_run_at.isoformat(timespec='seconds')}"


def build_startup_popup_run_key(*, task_id: int, user_id: int, launch_id: str) -> str:
    return f"popup_start:{int(task_id)}:{int(user_id)}:{str(launch_id).strip()}"


def validate_popup_task_payload(data: dict[str, Any]) -> dict[str, Any]:
    title = str(data.get("title") or "").strip()
    content = str(data.get("content") or "").strip()
    popup_type = normalize_popup_choice(data.get("type"), POPUP_TYPES)
    send_mode = normalize_popup_choice(data.get("send_mode"), SEND_MODES, "immediate")
    target_mode = normalize_popup_choice(data.get("target_mode"), TARGET_MODES, "all")
    status = normalize_popup_choice(data.get("status"), TASK_STATUSES, "draft")

    if not title:
        raise PopupValidationError("标题不能为空")
    if len(title) > 50:
        raise PopupValidationError("标题不能超过50字")
    if not content:
        raise PopupValidationError("正文不能为空")
    if popup_type not in POPUP_TYPES:
        raise PopupValidationError("弹窗类型不正确")
    if send_mode not in SEND_MODES:
        raise PopupValidationError("发送模式不正确")
    if target_mode not in TARGET_MODES:
        raise PopupValidationError("目标范围不正确")
    if status not in TASK_STATUSES:
        raise PopupValidationError("任务状态不正确")
    ensure_repeat_has_end_condition(
        send_mode=send_mode,
        end_at=data.get("end_at"),
        max_runs=data.get("max_runs"),
    )
    if target_mode == "user_ids" and not normalize_user_ids(data.get("target_user_ids")):
        raise PopupValidationError("请填写目标用户ID")
    target_filters = _normalize_target_filters(target_mode, data.get("target_filters"))
    if send_mode == "once" and data.get("publish_at") is None:
        raise PopupValidationError("一次性定时必须选择发布时间")
    if send_mode == "repeat":
        repeat_type = normalize_popup_choice(data.get("repeat_type"), REPEAT_TYPES)
        if repeat_type not in REPEAT_TYPES:
            raise PopupValidationError("周期类型仅支持每日、每周、每月")
        _parse_repeat_time(data.get("repeat_time"))
        if repeat_type == "weekly" and data.get("repeat_weekday") is None:
            raise PopupValidationError("每周重复必须选择周几")
        if repeat_type == "monthly" and data.get("repeat_month_day") is None:
            raise PopupValidationError("每月重复必须选择日期")

    payload = dict(data)
    payload.update(
        {
            "title": title,
            "content": content,
            "type": popup_type,
            "send_mode": send_mode,
            "target_mode": target_mode,
            "target_user_ids": normalize_user_ids(data.get("target_user_ids")),
            "target_filters": target_filters,
            "status": status,
            "repeat_type": normalize_popup_choice(data.get("repeat_type"), REPEAT_TYPES) or None,
            "publish_at": data.get("publish_at"),
        }
    )
    if send_mode != "repeat":
        payload.update(
            {
                "repeat_type": None,
                "repeat_time": None,
                "repeat_weekday": None,
                "repeat_month_day": None,
                "start_at": None,
                "end_at": None,
                "max_runs": None,
            }
        )
    if send_mode != "once":
        payload["publish_at"] = None
    return payload


def _target_query(target_mode: str, target_user_ids: list[int] | None, target_filters: dict[str, Any] | None) -> Q:
    q = Q()
    if target_mode == "user_ids":
        q &= Q(id__in=target_user_ids or [])
    elif target_mode == "filter":
        filters = target_filters or {}
        if "gender" in filters and filters["gender"]:
            q &= Q(gender=str(filters["gender"]))
        if "is_certified_user" in filters and filters["is_certified_user"] is not None:
            q &= Q(is_certified_user=bool(filters["is_certified_user"]))
    return q


async def resolve_target_user_ids(
    *,
    target_mode: str,
    target_user_ids: list[int] | None,
    target_filters: dict[str, Any] | None,
) -> list[int]:
    if target_mode == "filter":
        target_filters = _normalize_target_filters(target_mode, target_filters)
    q = _target_query(target_mode, target_user_ids, target_filters)
    rows = await AppUser.filter(q).values("id")
    return [int(row["id"]) for row in rows]


async def estimate_target_count(
    *,
    target_mode: str,
    target_user_ids: list[int] | str | None = None,
    target_filters: dict[str, Any] | None = None,
) -> int:
    normalized = normalize_user_ids(target_user_ids)
    if target_mode == "filter":
        target_filters = _normalize_target_filters(target_mode, target_filters)
    q = _target_query(target_mode, normalized, target_filters)
    return await AppUser.filter(q).count()


def _initial_task_status(data: dict[str, Any]) -> str:
    if data.get("status") == "draft":
        return "draft"
    if data["send_mode"] in {"repeat", "app_start"}:
        return "running"
    return "scheduled"


def _initial_next_run_at(data: dict[str, Any], now: datetime | None = None) -> datetime | None:
    now = _normalize_schedule_datetime(now) or now_local_naive()
    send_mode = data.get("send_mode")
    if data.get("status") == "draft":
        return None
    if send_mode == "immediate":
        return now
    if send_mode == "once":
        return _normalize_schedule_datetime(data.get("publish_at"))
    if send_mode == "repeat":
        start = _normalize_schedule_datetime(data.get("start_at")) or now
        after = start - timedelta(seconds=1)
        next_run_at = calculate_next_run_at(
            repeat_type=data["repeat_type"],
            after=after,
            repeat_time=data["repeat_time"],
            repeat_weekday=data.get("repeat_weekday"),
            repeat_month_day=data.get("repeat_month_day"),
        )
        if next_run_at < now:
            next_run_at = calculate_next_run_at(
                repeat_type=data["repeat_type"],
                after=now,
                repeat_time=data["repeat_time"],
                repeat_weekday=data.get("repeat_weekday"),
                repeat_month_day=data.get("repeat_month_day"),
            )
        return next_run_at
    return None


async def create_popup_task(data: dict[str, Any], *, created_by: int | None = None) -> SystemPopupTask:
    payload = validate_popup_task_payload(data)
    payload["created_by"] = created_by
    payload["status"] = _initial_task_status(payload)
    payload["next_run_at"] = _initial_next_run_at(payload)
    task = await SystemPopupTask.create(**payload)
    next_run_at = _normalize_schedule_datetime(task.next_run_at)
    if next_run_at and next_run_at <= now_local_naive():
        await publish_due_popup_task(task)
    return task


def _task_payload(task: SystemPopupTask, *, status: str | None = None) -> dict[str, Any]:
    return {
        "title": task.title,
        "content": task.content,
        "type": task.type,
        "send_mode": task.send_mode,
        "status": status or task.status,
        "target_mode": task.target_mode,
        "target_user_ids": task.target_user_ids or [],
        "target_filters": task.target_filters or None,
        "publish_at": task.publish_at,
        "repeat_type": task.repeat_type,
        "repeat_time": task.repeat_time,
        "repeat_weekday": task.repeat_weekday,
        "repeat_month_day": task.repeat_month_day,
        "start_at": task.start_at,
        "end_at": task.end_at,
        "max_runs": task.max_runs,
    }


async def activate_popup_task(task: SystemPopupTask) -> SystemPopupTask:
    payload = validate_popup_task_payload(_task_payload(task, status="scheduled"))
    task.status = _initial_task_status(payload)
    task.next_run_at = _initial_next_run_at(payload)
    await task.save()
    next_run_at = _normalize_schedule_datetime(task.next_run_at)
    if next_run_at and next_run_at <= now_local_naive():
        await publish_due_popup_task(task)
    return task


async def recalculate_popup_task_next_run_at(task: SystemPopupTask) -> SystemPopupTask:
    payload = validate_popup_task_payload(_task_payload(task))
    if task.status == "draft":
        task.next_run_at = None
    elif task.status in {"scheduled", "running"}:
        task.status = _initial_task_status({**payload, "status": "scheduled"})
        task.next_run_at = _initial_next_run_at({**payload, "status": "scheduled"})
    elif task.status == "paused" and payload["send_mode"] == "app_start":
        task.next_run_at = None
    await task.save()
    return task


async def publish_popup_task_once(task: SystemPopupTask, *, scheduled_run_at: datetime | None = None) -> SystemPopup:
    scheduled = (
        _normalize_schedule_datetime(scheduled_run_at)
        or _normalize_schedule_datetime(task.next_run_at)
        or _normalize_schedule_datetime(task.publish_at)
        or now_local_naive()
    )
    existing = await SystemPopup.filter(task_id=task.id, scheduled_run_at=scheduled).first()
    if existing:
        return existing
    run_key = build_popup_run_key(task_id=int(task.id), scheduled_run_at=scheduled)
    published_at = now_local_naive()
    async with in_transaction():
        try:
            popup = await SystemPopup.create(
                task_id=task.id,
                title=task.title,
                content=task.content,
                type=task.type,
                publish_at=task.publish_at or scheduled,
                published_at=published_at,
                scheduled_run_at=scheduled,
                run_key=run_key,
            )
        except IntegrityError:
            return await SystemPopup.filter(task_id=task.id, scheduled_run_at=scheduled).first()
    return popup


async def is_user_targeted_by_popup_task(
    *,
    user_id: int,
    target_mode: str,
    target_user_ids: list[int] | None,
    target_filters: dict[str, Any] | None,
) -> bool:
    if target_mode == "all":
        return True
    if target_mode == "user_ids":
        return int(user_id) in {int(item) for item in target_user_ids or []}
    if target_mode == "filter":
        filters = _normalize_target_filters(target_mode, target_filters)
        return await AppUser.filter(_target_query("filter", None, filters), id=int(user_id)).exists()
    return False


async def fetch_startup_popups_for_user(*, user_id: int, launch_id: str) -> list[dict[str, Any]]:
    launch_id = str(launch_id or "").strip()
    if not launch_id:
        raise PopupValidationError("启动标识不能为空")

    tasks = (
        await SystemPopupTask.filter(send_mode="app_start", status="running")
        .order_by("-created_at", "-id")
        .limit(STARTUP_POPUP_TASK_SCAN_LIMIT)
    )
    popups: list[dict[str, Any]] = []
    published_at = now_local_naive()
    for task in tasks:
        if len(popups) >= STARTUP_POPUP_RETURN_LIMIT:
            break
        if not await is_user_targeted_by_popup_task(
            user_id=user_id,
            target_mode=task.target_mode,
            target_user_ids=task.target_user_ids or [],
            target_filters=task.target_filters or None,
        ):
            continue

        run_key = build_startup_popup_run_key(task_id=int(task.id), user_id=int(user_id), launch_id=launch_id)
        popup = await SystemPopup.filter(run_key=run_key).first()
        if popup is None:
            async with in_transaction():
                try:
                    popup = await SystemPopup.create(
                        task_id=task.id,
                        title=task.title,
                        content=task.content,
                        type=task.type,
                        publish_at=published_at,
                        published_at=published_at,
                        scheduled_run_at=None,
                        run_key=run_key,
                    )
                    await SystemPopupReceipt.create(
                        popup_id=popup.id,
                        user_id=int(user_id),
                        pushed_at=published_at,
                    )
                except IntegrityError:
                    popup = await SystemPopup.filter(run_key=run_key).first()
                    if popup is None:
                        continue
        else:
            await SystemPopupReceipt.get_or_create(
                popup_id=popup.id,
                user_id=int(user_id),
                defaults={"pushed_at": popup.published_at or published_at},
            )

        popups.append(_dump_app_popup(popup))
    return popups


async def _get_popup_task(popup: SystemPopup) -> SystemPopupTask | None:
    task = getattr(popup, "task", None)
    if task is not None:
        return task
    task_id = getattr(popup, "task_id", None)
    if task_id is None:
        return None
    return await SystemPopupTask.filter(id=int(task_id)).first()


async def fetch_pending_popups_for_user(
    *,
    user_id: int,
    limit: int = PENDING_POPUP_RETURN_LIMIT,
) -> list[dict[str, Any]]:
    popups = (
        await SystemPopup.filter(published_at__not_isnull=True)
        .order_by("-published_at", "-id")
        .limit(PENDING_POPUP_SCAN_LIMIT)
    )
    items: list[dict[str, Any]] = []
    for popup in popups:
        if len(items) >= limit:
            break
        task = await _get_popup_task(popup)
        if task is None or getattr(task, "send_mode", None) == "app_start":
            continue
        if not await is_user_targeted_by_popup_task(
            user_id=user_id,
            target_mode=task.target_mode,
            target_user_ids=task.target_user_ids or [],
            target_filters=task.target_filters or None,
        ):
            continue

        receipt = await SystemPopupReceipt.filter(popup_id=int(popup.id), user_id=int(user_id)).first()
        if receipt is not None and receipt.ack_at is not None:
            continue
        if receipt is None:
            receipt, _ = await SystemPopupReceipt.get_or_create(
                popup_id=int(popup.id),
                user_id=int(user_id),
                defaults={"pushed_at": popup.published_at or now_local_naive()},
            )
            if receipt.ack_at is not None:
                continue

        items.append(_dump_app_popup(popup))
    return items


def _should_complete_repeat(task: SystemPopupTask, now: datetime) -> bool:
    if task.max_runs is not None and int(task.run_count or 0) >= int(task.max_runs):
        return True
    end_at = _normalize_schedule_datetime(task.end_at)
    if end_at is not None and now >= end_at:
        return True
    return False


async def publish_due_popup_task(task: SystemPopupTask, *, now: datetime | None = None) -> None:
    now = _normalize_schedule_datetime(now) or now_local_naive()
    next_run_at = _normalize_schedule_datetime(task.next_run_at)
    if task.send_mode == "app_start":
        return
    if task.status not in {"scheduled", "running"}:
        return
    if next_run_at is None or next_run_at > now:
        return
    scheduled = next_run_at
    await publish_popup_task_once(task, scheduled_run_at=scheduled)
    task.run_count = int(task.run_count or 0) + 1
    task.last_run_at = scheduled
    if task.send_mode in {"immediate", "once"}:
        task.status = "completed"
        task.next_run_at = None
    elif _should_complete_repeat(task, now):
        task.status = "completed"
        task.next_run_at = None
    else:
        next_run = calculate_next_run_at(
            repeat_type=task.repeat_type or "",
            after=scheduled,
            repeat_time=task.repeat_time or "",
            repeat_weekday=task.repeat_weekday,
            repeat_month_day=task.repeat_month_day,
        )
        end_at = _normalize_schedule_datetime(task.end_at)
        if end_at is not None and next_run > end_at:
            task.status = "completed"
            task.next_run_at = None
        else:
            task.next_run_at = next_run
    await task.save()


async def publish_due_popups(*, now: datetime | None = None, limit: int = 100) -> int:
    now = _normalize_schedule_datetime(now) or now_local_naive()
    tasks = (
        await SystemPopupTask.filter(
            status__in=["scheduled", "running"], next_run_at__not_isnull=True, next_run_at__lte=now
        )
        .order_by("next_run_at", "id")
        .limit(limit)
    )
    for task in tasks:
        await publish_due_popup_task(task, now=now)
    return len(tasks)


async def ack_user_popup(*, user_id: int, popup_id: int) -> bool:
    receipt = await SystemPopupReceipt.filter(popup_id=int(popup_id), user_id=int(user_id)).first()
    if not receipt:
        return False
    if receipt.ack_at is None:
        receipt.ack_at = now_local_naive()
        await receipt.save()
    return True


async def count_task_receipts(*, task_id: int) -> dict[str, int]:
    popup_ids = [int(row["id"]) for row in await SystemPopup.filter(task_id=task_id).values("id")]
    if not popup_ids:
        return {"pushed_count": 0, "ack_count": 0}
    pushed_count = await SystemPopupReceipt.filter(popup_id__in=popup_ids).count()
    ack_count = await SystemPopupReceipt.filter(popup_id__in=popup_ids, ack_at__not_isnull=True).count()
    return {"pushed_count": pushed_count, "ack_count": ack_count}


def _dump_app_popup(popup: SystemPopup) -> dict[str, Any]:
    return {
        "id": int(popup.id),
        "title": popup.title,
        "content": popup.content,
        "type": popup.type,
        "publish_at": format_popup_datetime(popup.published_at or popup.publish_at),
    }
