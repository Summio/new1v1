from typing import Literal, Optional

from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.models import AppUser
from app.schemas.base import Fail, Success, SuccessExtra
from app.services.active_pin_service import (
    clear_active_pin_cooldown,
    load_active_pin_cooldown_minutes,
    try_consume_active_pin_cooldown,
)
from app.services.customer_service import exclude_customer_service_user
from app.services.user_availability_service import (
    build_availability_payload_map,
    resolve_availability_payload,
)
from app.services.user_block_service import exclude_blocked_user_ids
from app.utils.media_url import normalize_media_list, to_relative_media_url

router = APIRouter()


@router.post("/certified-user/active-pin", summary="活跃页置顶")
async def active_pin_certified_user():
    app_user = CTX_APP_USER_OBJ.get()
    if not app_user:
        return Fail(code=401, msg="用户不存在")

    if app_user.status == "banned":
        return Fail(code=403, msg=f"账号已被封禁，原因：{app_user.ban_reason or '未知'}")
    if (app_user.status or "normal") != "normal":
        return Fail(code=403, msg="账号状态异常")
    if not bool(app_user.is_certified_user):
        return Fail(code=403, msg="仅真人认证用户可使用置顶")
    if bool(getattr(app_user, "video_dnd_enabled", False)):
        return Fail(code=400, msg="当前为勿扰状态，请关闭勿扰后再置顶")

    from app.websocket.presence import is_online, mark_online_since

    user_id = int(app_user.id)
    if not await is_online(user_id):
        return Fail(code=400, msg="请先保持在线后再置顶")

    cooldown_minutes = await load_active_pin_cooldown_minutes()
    cooldown_result = await try_consume_active_pin_cooldown(
        user_id=user_id,
        cooldown_minutes=cooldown_minutes,
    )
    if not cooldown_result.allowed:
        return Fail(
            code=429,
            msg="置顶太频繁，请稍后再试",
            data={"remaining_seconds": cooldown_result.remaining_seconds},
        )

    try:
        await mark_online_since(user_id, is_certified_user=True)
    except Exception:
        if cooldown_minutes > 0:
            await clear_active_pin_cooldown(user_id)
        return Fail(code=500, msg="置顶失败，请稍后重试")

    return Success(
        msg="已置顶",
        data={
            "cooldown_minutes": cooldown_minutes,
            "remaining_seconds": 0,
            "pinned_at_ms": cooldown_result.pinned_at_ms,
        },
    )


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
    availability_rank = _availability_sort_rank(user, online_ids)
    recommend_weight = int(user.recommend_weight or 0)

    if section == "active":
        if availability_rank > 0:
            return (availability_rank, online_since_map.get(user.id, 0), user.id)
        return (availability_rank, *_offline_review_sort_key(user))
    if section == "new":
        return (availability_rank, *_offline_review_sort_key(user))
    return (availability_rank, recommend_weight, *_offline_review_sort_key(user))


def _availability_sort_rank(user, online_ids: set[int]) -> int:
    try:
        user_id = int(user.id)
    except (TypeError, ValueError):
        return 0
    if user_id not in online_ids:
        return 0
    if bool(getattr(user, "video_dnd_enabled", False)):
        return 1
    return 2


def _offline_review_sort_key(user):
    reviewed_at = user.certification_reviewed_at
    return (reviewed_at is not None, reviewed_at, user.id)


async def _fetch_sorted_certified_user_page(q, section: str, page: int, page_size: int):
    from app.websocket.presence import (
        count_online_user_ids,
        filter_online_user_ids,
        get_online_user_id_page,
    )

    total = await q.count()
    offset = (page - 1) * page_size
    order_fields = {
        "recommend": ["-recommend_weight", "-certification_reviewed_at", "-id"],
        "active": ["-certification_reviewed_at", "-id"],
        "new": ["-certification_reviewed_at", "-id"],
    }[section]

    async def fetch_rank_by_db_order(rank: int, rank_offset: int, limit: int) -> tuple[int, list[AppUser]]:
        if limit <= 0:
            return 0, []
        batch_size = 200
        scan_offset = 0
        seen = 0
        users: list[AppUser] = []
        while True:
            candidates = list(await q.order_by(*order_fields).offset(scan_offset).limit(batch_size))
            if not candidates:
                break
            online_ids = await filter_online_user_ids(int(candidate.id) for candidate in candidates)
            for candidate in candidates:
                if _availability_sort_rank(candidate, online_ids) != rank:
                    continue
                if seen < rank_offset:
                    seen += 1
                    continue
                users.append(candidate)
                seen += 1
                if len(users) >= limit:
                    return seen, users
            scan_offset += len(candidates)
            if len(candidates) < batch_size:
                break
        return seen, users

    async def fetch_active_online_rank(
        rank: int, rank_offset: int, limit: int, online_total: int
    ) -> tuple[int, list[AppUser]]:
        if limit <= 0:
            return 0, []
        batch_size = 200
        scan_offset = 0
        seen = 0
        users: list[AppUser] = []
        while scan_offset < online_total:
            online_ids = await get_online_user_id_page(scan_offset, batch_size)
            scan_offset += batch_size
            if not online_ids:
                continue
            online_user_map = {int(user.id): user for user in await q.filter(id__in=online_ids)}
            for user_id in online_ids:
                candidate = online_user_map.get(user_id)
                if candidate is None:
                    continue
                if _availability_sort_rank(candidate, set(online_ids)) != rank:
                    continue
                if seen < rank_offset:
                    seen += 1
                    continue
                users.append(candidate)
                seen += 1
                if len(users) >= limit:
                    return seen, users
        return seen, users

    async def append_ranked_page(rank_fetchers) -> list[AppUser]:
        remaining_offset = offset
        users: list[AppUser] = []
        for fetcher in rank_fetchers:
            seen, rank_users = await fetcher(remaining_offset, page_size - len(users))
            users.extend(rank_users)
            if len(users) >= page_size:
                break
            remaining_offset = max(0, remaining_offset - seen)
        return users

    if section == "active":
        online_total = await count_online_user_ids()
        users = await append_ranked_page(
            [
                lambda rank_offset, limit: fetch_active_online_rank(2, rank_offset, limit, online_total),
                lambda rank_offset, limit: fetch_active_online_rank(1, rank_offset, limit, online_total),
                lambda rank_offset, limit: fetch_rank_by_db_order(0, rank_offset, limit),
            ]
        )
        return total, users

    users = await append_ranked_page(
        [
            lambda rank_offset, limit: fetch_rank_by_db_order(2, rank_offset, limit),
            lambda rank_offset, limit: fetch_rank_by_db_order(1, rank_offset, limit),
            lambda rank_offset, limit: fetch_rank_by_db_order(0, rank_offset, limit),
        ]
    )
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
    q = await exclude_customer_service_user(q)
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

    from app.websocket.presence import filter_online_user_ids

    online_ids = await filter_online_user_ids(int(user.id) for user in users)
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
