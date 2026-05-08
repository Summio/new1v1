from typing import Optional

from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.models import AppUser
from app.schemas.base import SuccessExtra
from app.utils.media_url import normalize_media_list, to_relative_media_url

router = APIRouter()


def _normalize_anchor_tags(raw_value) -> list[str]:
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


def _anchor_sort_key(user, section: str, online_ids: set[int], online_since_map: dict[int, int]):
    is_online = user.id in online_ids
    reviewed_at = user.anchor_reviewed_at
    recommend_weight = int(user.recommend_weight or 0)

    if section == "active":
        if is_online:
            return (True, online_since_map.get(user.id, 0), user.id)
        return (False, *_offline_review_sort_key(user))
    if section == "new":
        return (is_online, *_offline_review_sort_key(user))
    return (is_online, recommend_weight, *_offline_review_sort_key(user))


def _offline_review_sort_key(user):
    reviewed_at = user.anchor_reviewed_at
    return (reviewed_at is not None, reviewed_at, user.id)


async def _fetch_sorted_anchor_page(
    q, section: str, page: int, page_size: int, online_ids: set[int], online_since_map: dict[int, int]
):
    total = await q.count()
    offset = (page - 1) * page_size
    order_fields = {
        "recommend": ["-recommend_weight", "-anchor_reviewed_at", "-id"],
        "active": ["-anchor_reviewed_at", "-id"],
        "new": ["-anchor_reviewed_at", "-id"],
    }[section]

    if not online_ids:
        users = await q.order_by(*order_fields).offset(offset).limit(page_size)
        return total, list(users)

    online_q = q.filter(id__in=list(online_ids))
    online_total = await online_q.count()

    if section == "active":
        online_users = list(await online_q)
        online_users.sort(
            key=lambda user: online_since_map.get(user.id, 0),
            reverse=True,
        )
    else:
        online_users = list(await online_q.order_by(*order_fields))

    if offset < online_total:
        users = online_users[offset : offset + page_size]
        remaining = page_size - len(users)
        if remaining > 0:
            offline_users = await q.exclude(id__in=list(online_ids)).order_by(*order_fields).limit(remaining)
            users.extend(list(offline_users))
        return total, users

    offline_offset = offset - online_total
    users = await q.exclude(id__in=list(online_ids)).order_by(*order_fields).offset(offline_offset).limit(page_size)
    return total, list(users)


@router.get("/anchor/list", summary="主播推荐列表(分页)")
async def anchor_list(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=50, description="每页数量"),
    gender: Optional[str] = Query(None, description="性别过滤: male/female"),
    keyword: Optional[str] = Query(None, description="搜索关键字：用户ID或昵称"),
    section: str = Query("recommend", description="首页板块: recommend/active/new"),
):
    from app.websocket.presence import get_online_since_map, get_online_user_ids

    online_ids: set[int] = await get_online_user_ids()

    search_keyword = (keyword or "").strip()
    section_value = (section or "recommend").strip().lower()
    if section_value not in {"recommend", "active", "new"}:
        section_value = "recommend"

    filters = {"status": "normal"}
    if not search_keyword:
        filters["is_anchor"] = True
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

    if search_keyword:
        total = await q.count()
        users = await q.order_by("-id").offset((page - 1) * page_size).limit(page_size)
    else:
        online_since_map = await get_online_since_map()
        total, users = await _fetch_sorted_anchor_page(
            q=q,
            section=section_value,
            page=page,
            page_size=page_size,
            online_ids=online_ids,
            online_since_map=online_since_map,
        )

    rows = []
    for user in users:
        rows.append(
            {
                "id": user.id,
                "user_id": user.id,
                "nickname": user.nickname or user.phone,
                "avatar": to_relative_media_url(user.avatar),
                "cover_url": to_relative_media_url(user.cover_url),
                "album_photos": normalize_media_list(user.album_photos),
                "gender": user.gender or "secret",
                "birth_date": user.birth_date.isoformat() if user.birth_date else None,
                "height_cm": user.height_cm,
                "weight_kg": user.weight_kg,
                "location_city": user.location_city or "",
                "signature": user.signature or "",
                "intro": user.anchor_intro or "",
                "tags": _normalize_anchor_tags(user.anchor_tags),
                "call_price": int(user.anchor_call_price or 0),
                "is_online": user.id in online_ids,
                "status": user.status or "normal",
                "is_anchor": bool(user.is_anchor),
                "is_recommended": bool(user.is_recommended),
                "recommend_weight": int(user.recommend_weight or 0),
            }
        )

    has_more = total > page * page_size
    return SuccessExtra(rows=rows, current=page, total=total, has_more=has_more)
