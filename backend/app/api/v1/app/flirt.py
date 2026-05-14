from fastapi import APIRouter, Query

from app.api.v1.apis.system.flirt_config import _load_flirt_config
from app.core.ctx import CTX_APP_USER_OBJ
from app.models import AppUser
from app.schemas.base import Fail, SuccessExtra
from app.services.gift_income_service import decimal_to_float_2
from app.services.user_availability_service import (
    build_availability_payload_map,
    resolve_availability_payload,
)
from app.services.user_block_service import exclude_blocked_user_ids
from app.utils.media_url import normalize_media_list, to_relative_media_url

router = APIRouter()

FLIRT_AVAILABILITY_RANK = {
    "online": 3,
    "busy": 3,
    "dnd": 2,
    "offline": 1,
}


def _availability_rank(payload: dict) -> int:
    status = str(payload.get("availability_status") or "offline")
    return FLIRT_AVAILABILITY_RANK.get(status, 1)


def _serialize_flirt_user(user: AppUser, availability_payload: dict) -> dict:
    availability_payload = dict(availability_payload)
    availability_payload.setdefault("availability_status", "offline")
    availability_payload.setdefault("availability_label", "离线")
    return {
        "id": user.id,
        "user_id": user.id,
        "nickname": user.nickname or user.phone,
        "username": user.phone,
        "avatar": to_relative_media_url(user.avatar),
        "cover_url": to_relative_media_url(user.cover_url),
        "album_photos": normalize_media_list(user.album_photos),
        "gender": user.gender or "male",
        "birth_date": user.birth_date.isoformat() if user.birth_date else None,
        "height_cm": user.height_cm,
        "weight_kg": user.weight_kg,
        "location_city": user.location_city or "",
        "signature": user.signature or "",
        "coins": decimal_to_float_2(user.coins),
        "is_certified_user": bool(user.is_certified_user),
        "certification_status": user.certification_status or "none",
        "call_price": int(user.certified_call_price or 0),
        "text_dnd_enabled": bool(user.text_dnd_enabled),
        "status": user.status or "normal",
        "is_blocked_by_me": False,
        "has_blocked_me": False,
        **availability_payload,
    }


async def _fetch_flirt_user_page(q, page: int, page_size: int) -> tuple[int, list[tuple[AppUser, dict]]]:
    from app.websocket.presence import filter_online_user_ids

    total = await q.count()
    page_offset = (page - 1) * page_size
    candidate_batch_size = max(page_size * 4, 100)
    max_scan_batches = 20

    async def fetch_rank(rank: int, rank_offset: int, limit: int) -> tuple[int, list[tuple[AppUser, dict]]]:
        if limit <= 0:
            return 0, []

        scan_offset = 0
        scanned_batches = 0
        seen = 0
        selected: list[tuple[AppUser, dict]] = []

        while scanned_batches < max_scan_batches:
            candidates = list(await q.order_by("-coins", "-id").offset(scan_offset).limit(candidate_batch_size))
            if not candidates:
                break

            scanned_batches += 1
            online_ids = await filter_online_user_ids(int(user.id) for user in candidates)
            availability_payloads = await build_availability_payload_map(candidates, online_ids=online_ids)
            ranked_candidates: list[tuple[float, int, AppUser, dict]] = []
            for user in candidates:
                availability_payload = availability_payloads.get(
                    int(user.id),
                    resolve_availability_payload(user, is_online=False, is_busy=False),
                )
                if _availability_rank(availability_payload) != rank:
                    continue
                coins_value = decimal_to_float_2(user.coins)
                ranked_candidates.append((coins_value, int(user.id), user, availability_payload))

            ranked_candidates.sort(key=lambda item: (-item[0], -item[1]))
            for _coins_value, _user_id, user, availability_payload in ranked_candidates:
                if seen < rank_offset:
                    seen += 1
                    continue
                selected.append((user, availability_payload))
                seen += 1
                if len(selected) >= limit:
                    return seen, selected

            scan_offset += len(candidates)
            if len(candidates) < candidate_batch_size:
                break

        return seen, selected

    remaining_offset = page_offset
    selected: list[tuple[AppUser, dict]] = []
    for rank in (3, 2, 1):
        seen, rank_users = await fetch_rank(rank, remaining_offset, page_size - len(selected))
        selected.extend(rank_users)
        if len(selected) >= page_size:
            break
        remaining_offset = max(0, remaining_offset - seen)

    return total, selected


@router.get("/flirt/list", summary="搭讪用户列表")
async def flirt_user_list(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(20, ge=1, le=50, description="每页数量"),
):
    current_user = CTX_APP_USER_OBJ.get()
    if not current_user:
        return Fail(code=401, msg="用户不存在")
    if not bool(current_user.is_certified_user):
        return Fail(code=403, msg="仅真人认证用户可查看搭讪列表")

    config = await _load_flirt_config()
    q = AppUser.filter(status="normal").exclude(id=int(current_user.id))

    if config.filter_same_gender_enabled and current_user.gender:
        q = q.exclude(gender=current_user.gender)
    if config.filter_certified_user_enabled:
        q = q.filter(is_certified_user=False)

    blocked_user_ids = await exclude_blocked_user_ids(int(current_user.id))
    if blocked_user_ids:
        q = q.exclude(id__in=blocked_user_ids)

    total, users_with_availability = await _fetch_flirt_user_page(q=q, page=page, page_size=page_size)
    rows = [_serialize_flirt_user(user, availability_payload) for user, availability_payload in users_with_availability]
    has_more = total > page * page_size
    return SuccessExtra(rows=rows, current=page, total=total, has_more=has_more)
