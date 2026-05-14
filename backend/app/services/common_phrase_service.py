from datetime import datetime
from typing import Any

COMMON_PHRASE_SLOT_COUNT = 3
COMMON_PHRASE_MAX_LENGTH = 50
COMMON_PHRASE_STATUSES = {"none", "pending", "approved", "rejected"}


def _format_dt(value: Any) -> str | None:
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return value.isoformat()
    return str(value)


def validate_common_phrase_content(value: str | None) -> str:
    content = (value or "").strip()
    if not content:
        raise ValueError("请填写常用语内容")
    if len(content) > COMMON_PHRASE_MAX_LENGTH:
        raise ValueError(f"常用语最多{COMMON_PHRASE_MAX_LENGTH}字")
    return content


def validate_common_phrase_slot(slot_index: int) -> int:
    if slot_index < 1 or slot_index > COMMON_PHRASE_SLOT_COUNT:
        raise ValueError("常用语槽位不存在")
    return slot_index


def _phrase_to_dict(row: Any) -> dict:
    if isinstance(row, dict):
        source = row
        getter = source.get
    else:

        def getter(key: str, default: Any = None) -> Any:
            return getattr(row, key, default)

    status = (getter("review_status", "none") or "none").strip() or "none"
    if status not in COMMON_PHRASE_STATUSES:
        status = "none"
    return {
        "id": getter("id"),
        "user_id": int(getter("user_id", 0) or 0),
        "slot_index": int(getter("slot_index", 0) or 0),
        "approved_content": getter("approved_content", "") or "",
        "pending_content": getter("pending_content", "") or "",
        "review_status": status,
        "review_remark": getter("review_remark", "") or "",
        "submitted_at": _format_dt(getter("submitted_at")),
        "reviewed_at": _format_dt(getter("reviewed_at")),
        "reviewed_by": getter("reviewed_by"),
    }


def build_common_phrase_slots(rows: list[Any]) -> list[dict]:
    row_map = {int(_phrase_to_dict(row)["slot_index"]): _phrase_to_dict(row) for row in rows}
    slots: list[dict] = []
    for slot_index in range(1, COMMON_PHRASE_SLOT_COUNT + 1):
        row = row_map.get(slot_index)
        if row is None:
            row = {
                "id": None,
                "user_id": 0,
                "slot_index": slot_index,
                "approved_content": "",
                "pending_content": "",
                "review_status": "none",
                "review_remark": "",
                "submitted_at": None,
                "reviewed_at": None,
                "reviewed_by": None,
            }
        slots.append(row)
    return slots


def apply_common_phrase_review(row: dict, *, status: str, review_remark: str | None) -> dict:
    normalized_status = (status or "").strip()
    if normalized_status not in {"approved", "rejected"}:
        raise ValueError("审核结果必须为 approved 或 rejected")
    remark = (review_remark or "").strip()
    pending_content = (row.get("pending_content") or "").strip()
    if not pending_content:
        raise ValueError("没有待审核内容")
    if normalized_status == "rejected" and not remark:
        raise ValueError("驳回时必须填写审核备注")

    next_row = dict(row)
    next_row["review_status"] = normalized_status
    next_row["review_remark"] = "" if normalized_status == "approved" else remark
    next_row["reviewed_at"] = datetime.now()
    if normalized_status == "approved":
        next_row["approved_content"] = pending_content
        next_row["pending_content"] = ""
    return next_row
