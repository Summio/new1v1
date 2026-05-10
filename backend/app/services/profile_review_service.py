from __future__ import annotations

from collections.abc import Iterable

from app.utils.media_url import normalize_media_list, to_relative_media_url


class ProfileReviewValidationError(ValueError):
    pass


_REVIEW_FIELDS = ("nickname", "avatar", "signature", "album_photos")


def _text_value(value) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _normalize_album(value) -> list[str]:
    return normalize_media_list(value)


def _normalize_snapshot(source: dict | None) -> dict:
    source = source or {}
    return {
        "nickname": _text_value(source.get("nickname")),
        "avatar": to_relative_media_url(source.get("avatar")),
        "signature": _text_value(source.get("signature")),
        "album_photos": _normalize_album(source.get("album_photos")),
        "cover_url": to_relative_media_url(source.get("cover_url")),
    }


def _build_simple_item(field: str, before: str, after: str) -> dict:
    return {
        "item_id": field,
        "field": field,
        "label": {"nickname": "昵称", "avatar": "头像", "signature": "个性签名", "cover_url": "封面"}[field],
        "op": "replace",
        "before": before,
        "after": after,
        "status": "pending",
        "review_remark": "",
        "reviewed_at": None,
        "reviewed_by": None,
    }


def build_profile_review_payload(current: dict | None, target: dict | None) -> dict:
    before_snapshot = _normalize_snapshot(current)
    after_snapshot = _normalize_snapshot(target)

    review_items: list[dict] = []
    for field in ("nickname", "avatar", "signature"):
        before = before_snapshot[field]
        after = after_snapshot[field]
        if before != after:
            review_items.append(_build_simple_item(field, before, after))

    current_album = before_snapshot["album_photos"]
    target_album = after_snapshot["album_photos"]
    for idx, photo in enumerate(target_album):
        if photo not in current_album:
            review_items.append(
                {
                    "item_id": f"album_photos:add:{idx}",
                    "field": "album_photos",
                    "label": "相册",
                    "op": "add",
                    "before": None,
                    "after": photo,
                    "status": "pending",
                    "review_remark": "",
                    "reviewed_at": None,
                    "reviewed_by": None,
                }
            )

    return {
        "before_snapshot": before_snapshot,
        "after_snapshot": after_snapshot,
        "review_items": review_items,
    }


def review_items_have_pending(items: Iterable[dict]) -> bool:
    return any((item.get("status") or "pending") == "pending" for item in items)


def update_review_item_status(
    items: list[dict],
    *,
    item_id: str,
    status: str,
    reviewed_by: int | None = None,
    review_remark: str | None = None,
) -> list[dict]:
    next_items: list[dict] = []
    matched = False
    for item in items:
        next_item = dict(item)
        if next_item.get("item_id") == item_id:
            matched = True
            next_item["status"] = status
            next_item["reviewed_by"] = reviewed_by
            next_item["review_remark"] = (review_remark or "").strip()
        next_items.append(next_item)
    if not matched:
        raise ProfileReviewValidationError("审核项不存在")
    return next_items


def mark_all_review_items(
    items: list[dict],
    *,
    status: str,
    reviewed_by: int | None = None,
) -> list[dict]:
    next_items: list[dict] = []
    for item in items:
        next_item = dict(item)
        if (next_item.get("status") or "pending") == "pending":
            next_item["status"] = status
            next_item["reviewed_by"] = reviewed_by
            next_item["review_remark"] = ""
        next_items.append(next_item)
    return next_items


def apply_approved_profile_review_items(
    *,
    before_snapshot: dict | None,
    after_snapshot: dict | None,
    review_items: list[dict],
) -> dict:
    before_snapshot = _normalize_snapshot(before_snapshot)
    after_snapshot = _normalize_snapshot(after_snapshot)

    approved_map = {
        item.get("item_id"): item for item in review_items if (item.get("status") or "pending") == "approved"
    }

    update_data: dict = {}
    for field in ("nickname", "avatar", "signature"):
        item = approved_map.get(field)
        if item:
            update_data[field] = item.get("after")

    target_album = after_snapshot["album_photos"]
    approved_additions = {
        _text_value(item.get("after"))
        for item in review_items
        if item.get("field") == "album_photos"
        and item.get("op") == "add"
        and (item.get("status") or "pending") == "approved"
    }
    current_album = before_snapshot["album_photos"]

    final_album: list[str] = []
    seen: set[str] = set()
    for photo in target_album:
        if photo in current_album or photo in approved_additions:
            if photo not in seen:
                final_album.append(photo)
                seen.add(photo)
    if len(final_album) > 6:
        raise ProfileReviewValidationError("相册最多上传6张照片")

    update_data["album_photos"] = final_album

    target_cover = after_snapshot["cover_url"]
    current_cover = before_snapshot["cover_url"]
    if target_cover and target_cover in final_album:
        update_data["cover_url"] = target_cover
    elif current_cover and current_cover in final_album:
        update_data["cover_url"] = current_cover
    else:
        update_data["cover_url"] = final_album[0] if final_album else None

    if update_data["cover_url"] and update_data["cover_url"] not in final_album:
        raise ProfileReviewValidationError("封面必须存在于最终相册")

    return update_data
