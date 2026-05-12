from typing import Literal, Optional

from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.core.ctx import CTX_APP_USER_ID
from app.models import AppUser
from app.schemas.base import SuccessExtra
from app.services.user_availability_service import (
    build_availability_payload_map,
    resolve_availability_payload,
)
from app.services.user_block_service import exclude_blocked_user_ids
from app.utils.media_url import normalize_media_list, to_relative_media_url

router = APIRouter()


def _normalize_certified_tags(raw_value) -> list[str]:
    if not isinstance(raw_value, list):
        return []
    out: list[str] = []
    for item in raw_value:
        if not isinstance(item, str):
            continue
        tag = item.strip()
        if tag:
            out.append(tag)
    return out


def _certified_user_sort_key(user, section: str, online_ids: set[int], online_since_map: dict[int, int]):
    is_online = user.id in online_ids
    recommend_weight = int(user.recommend_weight or 0)

    if section == "active":
        if is_online:
            return (True, online_since_map.get(user.id, 0), user.id)
        return (False, *_offline_review_sort_key(user))
    if section == "new":
        return (is_online, *_offline_review_sort_key(user))
    return (is_online, recommend_weight, *_offline_review_sort_key(user))


def _offline_review_sort_key(user):
    reviewed_at = user.certification_reviewed_at
    return (reviewed_at is not None, reviewed_at, user.id)


async def _fetch_sorted_certified_user_page(q, section: str, page: int, page_size: int):
    from app.websocket.presence import count_online_user_ids, get_online_user_id_page
    from app.websocket.presence import is_online as _is_online_user

    total = await q.count()
    offset = (page - 1) * page_size
    order_fields = {
        "recommend": ["-recommend_weight", "-certification_reviewed_at", "-id"],
        "active": ["-certification_reviewed_at", "-id"],
        "new": ["-certification_reviewed_at", "-id"],
    }[section]

    online_total = await count_online_user_ids()

    async def fetch_online_by_db_order() -> list[AppUser]:
        needed = offset + page_size
        batch_size = min(max(needed * 2, page_size), 200)
        scan_offset = 0
        online_users: list[AppUser] = []
        while len(online_users) < needed and scan_offset < 1000:
            candidates = list(await q.order_by(*order_fields).offset(scan_offset).limit(batch_size))
            if not candidates:
                break
            for candidate in candidates:
                if await _is_online_user(int(candidate.id)):
                    online_users.append(candidate)
                    if len(online_users) >= needed:
                        break
            scan_offset += len(candidates)
            if len(candidates) < batch_size:
                break
        return online_users[offset : offset + page_size]

    async def fetch_offline_by_db_order(offline_offset: int, limit: int) -> list[AppUser]:
        if limit <= 0:
            return []
        batch_size = min(max(limit * 4, 50), 200)
        scan_offset = 0
        skipped = 0
        users: list[AppUser] = []
        while len(users) < limit and scan_offset < offline_offset + 1000:
            candidates = list(await q.order_by(*order_fields).offset(scan_offset).limit(batch_size))
            if not candidates:
                break
            for candidate in candidates:
                if await _is_online_user(int(candidate.id)):
                    continue
                if skipped < offline_offset:
                    skipped += 1
                    continue
                users.append(candidate)
                if len(users) >= limit:
                    break
            scan_offset += len(candidates)
            if len(candidates) < batch_size:
                break
        return users

    if online_total <= 0:
        users = await fetch_offline_by_db_order(offset, page_size)
        return total, users

    if offset < online_total:
        if section == "active":
            online_ids = await get_online_user_id_page(offset, page_size)
            online_map = {int(user.id): user for user in await q.filter(id__in=online_ids)}
            users = [online_map[user_id] for user_id in online_ids if user_id in online_map]
        else:
            users = await fetch_online_by_db_order()
        remaining = page_size - len(users)
        if remaining > 0:
            offline_users = await fetch_offline_by_db_order(0, remaining)
            users.extend(list(offline_users))
        return total, users

    offline_offset = offset - online_total
    users = await fetch_offline_by_db_order(offline_offset, page_size)
    return total, users


@router.get("/certified-user/list", summary="认证用户推荐列表(分页)")
async def certified_user_list(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=50, description="每页数量"),
    gender: Optional[Literal["male", "female"]] = Query(None, description="性别过滤: male/female"),
    keyword: Optional[str] = Query(None, description="搜索关键字：用户ID或昵称"),
    section: str = Query("recommend", description="首页板块: recommend/active/new"),
):
    search_keyword = (keyword or "").strip()
    section_value = (section or "recommend").strip().lower()
    if section_value not in {"recommend", "active", "new"}:
        section_value = "recommend"

    filters = {"status": "normal"}
    if not search_keyword:
        filters["is_certified_user"] = True
        filters["cover_url__not_isnull"] = True
        if section_value == "recommend":
            filters["is_recommended"] = True

    q = AppUser.filter(**filters)
    if not search_keyword:
        q = q.exclude(cover_url="")
    if gender:
        q = q.filter(gender=gender)
    if search_keyword:
        keyword_q = Q(nickname__icontains=search_keyword)
        if search_keyword.isdigit():
            keyword_q |= Q(id=int(search_keyword))
        q = q.filter(keyword_q)

    blocked_user_ids = await exclude_blocked_user_ids(int(CTX_APP_USER_ID.get() or 0))
    if blocked_user_ids:
        q = q.exclude(id__in=blocked_user_ids)

    if search_keyword:
        total = await q.count()
        users = await q.order_by("-id").offset((page - 1) * page_size).limit(page_size)
    else:
        total, users = await _fetch_sorted_certified_user_page(
            q=q,
            section=section_value,
            page=page,
            page_size=page_size,
        )

    from app.websocket.presence import is_online as _is_online_user

    online_ids: set[int] = set()
    for user in users:
        if await _is_online_user(int(user.id)):
            online_ids.add(int(user.id))
    availability_payloads = await build_availability_payload_map(users, online_ids=online_ids)

    rows = []
    for user in users:
        user_id = int(user.id)
        availability_payload = availability_payloads.get(
            user_id,
            resolve_availability_payload(user, is_online=False, is_busy=False),
        )
        rows.append(
            {
                "id": user.id,
                "user_id": user.id,
                "nickname": user.nickname or user.phone,
                "avatar": to_relative_media_url(user.avatar),
                "cover_url": to_relative_media_url(user.cover_url),
                "album_photos": normalize_media_list(user.album_photos),
                "gender": user.gender or "male",
                "birth_date": user.birth_date.isoformat() if user.birth_date else None,
                "height_cm": user.height_cm,
                "weight_kg": user.weight_kg,
                "location_city": user.location_city or "",
                "signature": user.signature or "",
                "intro": user.certified_intro or "",
                "tags": _normalize_certified_tags(user.certified_tags),
                "call_price": int(user.certified_call_price or 0),
                **availability_payload,
                "status": user.status or "normal",
                "is_certified_user": bool(user.is_certified_user),
                "is_recommended": bool(user.is_recommended),
                "recommend_weight": int(user.recommend_weight or 0),
            }
        )

    has_more = total > page * page_size
    return SuccessExtra(rows=rows, current=page, total=total, has_more=has_more)
