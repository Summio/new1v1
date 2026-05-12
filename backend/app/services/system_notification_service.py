from __future__ import annotations

import calendar
from datetime import datetime, time, timedelta
from typing import Any

from tortoise.exceptions import IntegrityError
from tortoise.expressions import Q
from tortoise.transactions import in_transaction

from app.core.time_utils import now_local_naive
from app.models import (
    AppUser,
    SystemNotification,
    SystemNotificationReceipt,
    SystemNotificationTask,
)
from app.websocket.events import push_system_notification_unread_changed

NOTIFICATION_TYPES = {"announcement", "account", "review", "interaction"}
SEND_MODES = {"immediate", "once", "repeat"}
TASK_STATUSES = {"draft", "scheduled", "running", "paused", "completed", "cancelled"}
TARGET_MODES = {"all", "user_ids", "filter"}
REPEAT_TYPES = {"daily", "weekly", "monthly"}


class NotificationValidationError(ValueError):
    pass


def normalize_user_ids(value: list[int | str] | str | None) -> list[int]:
    if value is None or value == "":
        return []
    raw_items: list[int | str]
    if isinstance(value, str):
        raw_items = [item.strip() for item in value.split(",") if item.strip()]
    elif isinstance(value, list):
        raw_items = value
    else:
        raise NotificationValidationError("用户ID格式不正确")

    user_ids: set[int] = set()
    for item in raw_items:
        try:
            user_id = int(item)
        except (TypeError, ValueError) as exc:
            raise NotificationValidationError("用户ID必须是正整数") from exc
        if user_id <= 0:
            raise NotificationValidationError("用户ID必须是正整数")
        user_ids.add(user_id)
    return sorted(user_ids)


def ensure_repeat_has_end_condition(
    *,
    send_mode: str,
    end_at: datetime | None,
    max_runs: int | None,
) -> None:
    if send_mode == "repeat" and end_at is None and max_runs is None:
        raise NotificationValidationError("周期重复必须填写结束时间或最大发送次数")
    if max_runs is not None and max_runs <= 0:
        raise NotificationValidationError("最大发送次数必须大于0")


def _parse_repeat_time(value: str | None) -> time:
    if not value:
        raise NotificationValidationError("周期重复必须填写发送时间")
    try:
        hour, minute = [int(part) for part in value.split(":", 1)]
    except (ValueError, AttributeError) as exc:
        raise NotificationValidationError("发送时间格式必须为 HH:mm") from exc
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        raise NotificationValidationError("发送时间格式必须为 HH:mm")
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
            raise NotificationValidationError("每周重复必须选择周几")
        days = (repeat_weekday - after.weekday()) % 7
        candidate = datetime.combine((after + timedelta(days=days)).date(), run_time)
        if candidate <= after:
            candidate += timedelta(days=7)
        return candidate

    if repeat_type == "monthly":
        if repeat_month_day is None or repeat_month_day < 1 or repeat_month_day > 31:
            raise NotificationValidationError("每月重复必须选择日期")
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
        raise NotificationValidationError("无法计算下一次发送时间")

    raise NotificationValidationError("周期类型仅支持 daily/weekly/monthly")


def build_run_key(*, task_id: int, scheduled_run_at: datetime) -> str:
    return f"task:{int(task_id)}:{scheduled_run_at.isoformat(timespec='seconds')}"


def build_business_notification_key(biz_type: str, biz_id: int | str, user_id: int) -> str:
    return f"{biz_type}:{biz_id}:{int(user_id)}"


def validate_task_payload(data: dict[str, Any]) -> dict[str, Any]:
    title = str(data.get("title") or "").strip()
    summary = str(data.get("summary") or "").strip()
    content = str(data.get("content") or "").strip()
    notification_type = str(data.get("type") or "").strip()
    send_mode = str(data.get("send_mode") or "immediate").strip()
    target_mode = str(data.get("target_mode") or "all").strip()
    status = str(data.get("status") or "draft").strip()

    if not title or not summary or not content:
        raise NotificationValidationError("标题、摘要和正文不能为空")
    if notification_type not in NOTIFICATION_TYPES:
        raise NotificationValidationError("通知类型不正确")
    if send_mode not in SEND_MODES:
        raise NotificationValidationError("发送模式不正确")
    if target_mode not in TARGET_MODES:
        raise NotificationValidationError("目标范围不正确")
    if status not in TASK_STATUSES:
        raise NotificationValidationError("任务状态不正确")
    ensure_repeat_has_end_condition(
        send_mode=send_mode,
        end_at=data.get("end_at"),
        max_runs=data.get("max_runs"),
    )
    if target_mode == "user_ids" and not normalize_user_ids(data.get("target_user_ids")):
        raise NotificationValidationError("请填写目标用户ID")
    if target_mode == "filter" and not (data.get("target_filters") or {}):
        raise NotificationValidationError("请至少选择一个筛选条件")

    if send_mode == "once" and data.get("publish_at") is None:
        raise NotificationValidationError("一次性定时必须选择发布时间")

    if send_mode == "repeat":
        repeat_type = data.get("repeat_type")
        if repeat_type not in REPEAT_TYPES:
            raise NotificationValidationError("周期类型仅支持每日、每周、每月")
        _parse_repeat_time(data.get("repeat_time"))
        if repeat_type == "weekly" and data.get("repeat_weekday") is None:
            raise NotificationValidationError("每周重复必须选择周几")
        if repeat_type == "monthly" and data.get("repeat_month_day") is None:
            raise NotificationValidationError("每月重复必须选择日期")

    data = dict(data)
    data.update(
        {
            "title": title,
            "summary": summary,
            "content": content,
            "type": notification_type,
            "send_mode": send_mode,
            "target_mode": target_mode,
            "target_user_ids": normalize_user_ids(data.get("target_user_ids")),
            "target_filters": data.get("target_filters") or None,
            "status": status,
        }
    )
    return data


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
        if "certification_status" in filters and filters["certification_status"]:
            q &= Q(certification_status=str(filters["certification_status"]))
        if "status" in filters and filters["status"]:
            q &= Q(status=str(filters["status"]))
    return q


async def resolve_target_user_ids(
    *,
    target_mode: str,
    target_user_ids: list[int] | None,
    target_filters: dict[str, Any] | None,
) -> list[int]:
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
    q = _target_query(target_mode, normalized, target_filters)
    return await AppUser.filter(q).count()


def _initial_task_status(data: dict[str, Any]) -> str:
    if data.get("status") == "draft":
        return "draft"
    if data["send_mode"] == "repeat":
        return "running"
    if data["send_mode"] == "once":
        return "scheduled"
    return "scheduled"


def _initial_next_run_at(data: dict[str, Any], now: datetime | None = None) -> datetime | None:
    now = now or now_local_naive()
    send_mode = data.get("send_mode")
    if data.get("status") == "draft":
        return None
    if send_mode == "immediate":
        return now
    if send_mode == "once":
        return data.get("publish_at")
    if send_mode == "repeat":
        start = data.get("start_at") or now
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


async def create_notification_task(data: dict[str, Any], *, created_by: int | None = None) -> SystemNotificationTask:
    payload = validate_task_payload(data)
    payload["created_by"] = created_by
    payload["status"] = _initial_task_status(payload)
    payload["next_run_at"] = _initial_next_run_at(payload)
    task = await SystemNotificationTask.create(**payload)
    if task.next_run_at and task.next_run_at <= now_local_naive():
        await publish_due_task(task)
    return task


def _task_payload(task: SystemNotificationTask, *, status: str | None = None) -> dict[str, Any]:
    return {
        "title": task.title,
        "summary": task.summary,
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


async def activate_notification_task(task: SystemNotificationTask) -> SystemNotificationTask:
    payload = validate_task_payload(_task_payload(task, status="scheduled"))
    task.status = _initial_task_status(payload)
    task.next_run_at = _initial_next_run_at(payload)
    await task.save()
    if task.next_run_at and task.next_run_at <= now_local_naive():
        await publish_due_task(task)
    return task


async def recalculate_task_next_run_at(task: SystemNotificationTask) -> SystemNotificationTask:
    payload = validate_task_payload(_task_payload(task))
    if task.status == "draft":
        task.next_run_at = None
    elif task.status in {"scheduled", "running"}:
        task.status = _initial_task_status({**payload, "status": "scheduled"})
        task.next_run_at = _initial_next_run_at({**payload, "status": "scheduled"})
    await task.save()
    return task


async def publish_task_once(
    task: SystemNotificationTask, *, scheduled_run_at: datetime | None = None
) -> SystemNotification | None:
    scheduled = scheduled_run_at or task.next_run_at or task.publish_at or now_local_naive()
    run_key = build_run_key(task_id=int(task.id), scheduled_run_at=scheduled)
    existing = await SystemNotification.filter(task_id=task.id, scheduled_run_at=scheduled).first()
    if existing:
        return existing

    target_user_ids = await resolve_target_user_ids(
        target_mode=task.target_mode,
        target_user_ids=task.target_user_ids or [],
        target_filters=task.target_filters or None,
    )
    if not target_user_ids:
        return None

    async with in_transaction():
        try:
            notification = await SystemNotification.create(
                task_id=task.id,
                title=task.title,
                summary=task.summary,
                content=task.content,
                type=task.type,
                source="admin",
                publish_at=task.publish_at or scheduled,
                published_at=now_local_naive(),
                scheduled_run_at=scheduled,
                run_key=run_key,
            )
        except IntegrityError:
            return await SystemNotification.filter(task_id=task.id, scheduled_run_at=scheduled).first()
        receipts = [
            SystemNotificationReceipt(notification_id=notification.id, user_id=user_id) for user_id in target_user_ids
        ]
        await SystemNotificationReceipt.bulk_create(receipts, ignore_conflicts=True)

    for user_id in target_user_ids:
        await _push_unread_changed(user_id)
    return notification


def _should_complete_repeat(task: SystemNotificationTask, now: datetime) -> bool:
    if task.max_runs is not None and int(task.run_count or 0) >= int(task.max_runs):
        return True
    if task.end_at is not None and now >= task.end_at:
        return True
    return False


async def publish_due_task(task: SystemNotificationTask, *, now: datetime | None = None) -> None:
    now = now or now_local_naive()
    if task.status not in {"scheduled", "running"}:
        return
    if task.next_run_at is None or task.next_run_at > now:
        return

    scheduled = task.next_run_at
    await publish_task_once(task, scheduled_run_at=scheduled)
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
        if task.end_at is not None and next_run > task.end_at:
            task.status = "completed"
            task.next_run_at = None
        else:
            task.next_run_at = next_run
    await task.save()


async def publish_due_notifications(*, now: datetime | None = None, limit: int = 100) -> int:
    now = now or now_local_naive()
    tasks = (
        await SystemNotificationTask.filter(
            status__in=["scheduled", "running"], next_run_at__not_isnull=True, next_run_at__lte=now
        )
        .order_by("next_run_at", "id")
        .limit(limit)
    )
    for task in tasks:
        await publish_due_task(task, now=now)
    return len(tasks)


async def create_business_notification(
    *,
    user_id: int,
    title: str,
    summary: str,
    content: str,
    type: str,
    biz_key: str,
) -> SystemNotification | None:
    if await SystemNotification.filter(biz_key=biz_key).exists():
        return await SystemNotification.filter(biz_key=biz_key).first()
    try:
        notification = await SystemNotification.create(
            title=title.strip(),
            summary=summary.strip(),
            content=content.strip(),
            type=type,
            source="system",
            publish_at=now_local_naive(),
            published_at=now_local_naive(),
            biz_key=biz_key,
        )
    except IntegrityError:
        return await SystemNotification.filter(biz_key=biz_key).first()
    await SystemNotificationReceipt.create(notification_id=notification.id, user_id=int(user_id))
    await _push_unread_changed(int(user_id))
    return notification


async def list_user_notifications(*, user_id: int, page: int, page_size: int) -> tuple[list[dict[str, Any]], int]:
    total = await SystemNotificationReceipt.filter(user_id=user_id).count()
    receipts = (
        await SystemNotificationReceipt.filter(user_id=user_id)
        .order_by("-created_at", "-id")
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    notification_ids = [int(row.notification_id) for row in receipts]
    notifications = await SystemNotification.filter(id__in=notification_ids).all()
    by_id = {int(item.id): item for item in notifications}
    rows: list[dict[str, Any]] = []
    for receipt in receipts:
        notification = by_id.get(int(receipt.notification_id))
        if not notification:
            continue
        rows.append(_dump_user_notification(notification, receipt))
    return rows, total


async def get_user_unread_summary(*, user_id: int) -> dict[str, Any]:
    unread_count = await SystemNotificationReceipt.filter(user_id=user_id, read_at__isnull=True).count()
    latest_receipt = await SystemNotificationReceipt.filter(user_id=user_id).order_by("-created_at", "-id").first()
    latest = None
    if latest_receipt:
        notification = await SystemNotification.filter(id=latest_receipt.notification_id).first()
        if notification:
            latest = {
                "id": int(notification.id),
                "title": notification.title,
                "summary": notification.summary,
                "type": notification.type,
                "publish_at": notification.published_at or notification.publish_at,
            }
    return {"count": unread_count, "latest": latest}


async def get_user_notification_detail(*, user_id: int, notification_id: int) -> dict[str, Any] | None:
    receipt = await SystemNotificationReceipt.filter(user_id=user_id, notification_id=notification_id).first()
    if not receipt:
        return None
    notification = await SystemNotification.filter(id=notification_id).first()
    if not notification:
        return None
    if receipt.read_at is None:
        receipt.read_at = now_local_naive()
        await receipt.save()
        await _push_unread_changed(user_id)
    return _dump_user_notification(notification, receipt, include_content=True)


async def mark_notification_read(*, user_id: int, notification_id: int) -> bool:
    receipt = await SystemNotificationReceipt.filter(user_id=user_id, notification_id=notification_id).first()
    if not receipt:
        return False
    if receipt.read_at is None:
        receipt.read_at = now_local_naive()
        await receipt.save()
        await _push_unread_changed(user_id)
    return True


async def mark_notification_unread(*, user_id: int, notification_id: int) -> bool:
    receipt = await SystemNotificationReceipt.filter(user_id=user_id, notification_id=notification_id).first()
    if not receipt:
        return False
    if receipt.read_at is not None:
        receipt.read_at = None
        await receipt.save()
        await _push_unread_changed(user_id)
    return True


async def mark_all_notifications_read(*, user_id: int) -> int:
    now = now_local_naive()
    updated = await SystemNotificationReceipt.filter(user_id=user_id, read_at__isnull=True).update(read_at=now)
    if updated:
        await _push_unread_changed(user_id)
    return updated


def _dump_user_notification(
    notification: SystemNotification,
    receipt: SystemNotificationReceipt,
    *,
    include_content: bool = False,
) -> dict[str, Any]:
    data = {
        "id": int(notification.id),
        "title": notification.title,
        "summary": notification.summary,
        "type": notification.type,
        "publish_at": notification.published_at or notification.publish_at,
        "read_at": receipt.read_at,
        "is_read": receipt.read_at is not None,
    }
    if include_content:
        data["content"] = notification.content
    return data


async def _push_unread_changed(user_id: int) -> None:
    try:
        summary = await get_user_unread_summary(user_id=user_id)
        await push_system_notification_unread_changed(user_id=user_id, unread_count=int(summary["count"]))
    except Exception:
        return
