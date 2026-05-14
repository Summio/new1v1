from fastapi import APIRouter, BackgroundTasks, Query
from loguru import logger

from app.api.v1.apis.system.flirt_config import _load_flirt_config
from app.core.ctx import CTX_APP_USER_OBJ
from app.core.redis import get_redis
from app.models import AppUser, AppUserCommonPhrase
from app.schemas.app_api import FlirtGreetIn
from app.schemas.base import Fail, Success, SuccessExtra
from app.services.flirt_greet_service import (
    get_greet_quota,
    release_greet_quota,
    reserve_greet_quota,
    set_greet_cooldown,
)
from app.services.gift_income_service import decimal_to_float_2
from app.services.tim_service import send_text_message
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


async def _build_flirt_user_query(current_user: AppUser, config):
    q = AppUser.filter(status="normal").exclude(id=int(current_user.id))
    if config.filter_same_gender_enabled and current_user.gender:
        q = q.exclude(gender=current_user.gender)
    if config.filter_certified_user_enabled:
        q = q.filter(is_certified_user=False)

    blocked_user_ids = await exclude_blocked_user_ids(int(current_user.id))
    if blocked_user_ids:
        q = q.exclude(id__in=blocked_user_ids)
    return q


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


async def _fetch_online_flirt_users(current_user: AppUser, config) -> list[AppUser]:
    from app.websocket.presence import get_online_user_ids

    online_ids = await get_online_user_ids()
    online_ids.discard(int(current_user.id))
    if not online_ids:
        return []
    q = await _build_flirt_user_query(current_user, config)
    return list(await q.filter(id__in=list(online_ids)).order_by("-coins", "-id"))


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
    q = await _build_flirt_user_query(current_user, config)

    total, users_with_availability = await _fetch_flirt_user_page(q=q, page=page, page_size=page_size)
    rows = [_serialize_flirt_user(user, availability_payload) for user, availability_payload in users_with_availability]
    has_more = total > page * page_size
    return SuccessExtra(rows=rows, current=page, total=total, has_more=has_more)


@router.get("/flirt/greet/quota", summary="搭讪打招呼额度")
async def flirt_greet_quota():
    current_user = CTX_APP_USER_OBJ.get()
    if not current_user:
        return Fail(code=401, msg="用户不存在")
    if not bool(current_user.is_certified_user):
        return Fail(code=403, msg="仅真人认证用户可使用打招呼")

    config = await _load_flirt_config()
    try:
        redis = await get_redis()
        quota = await get_greet_quota(redis, user_id=int(current_user.id), daily_limit=int(config.greet_daily_limit))
    except Exception:
        return Fail(code=503, msg="打招呼次数检查失败，请稍后重试")
    return Success(data=quota)


@router.post("/flirt/greet", summary="搭讪页打招呼")
async def flirt_greet(req_in: FlirtGreetIn, background_tasks: BackgroundTasks):
    current_user = CTX_APP_USER_OBJ.get()
    if not current_user:
        return Fail(code=401, msg="用户不存在")
    if not bool(current_user.is_certified_user):
        return Fail(code=403, msg="仅真人认证用户可使用打招呼")

    phrase = await AppUserCommonPhrase.filter(user_id=int(current_user.id), slot_index=req_in.slot_index).first()
    content = (phrase.approved_content if phrase else "").strip()
    if not content:
        return Fail(code=400, msg="该常用语还没有通过审核")

    config = await _load_flirt_config()
    try:
        redis = await get_redis()
        quota_status, quota = await reserve_greet_quota(
            redis,
            user_id=int(current_user.id),
            daily_limit=int(config.greet_daily_limit),
        )
    except Exception:
        return Fail(code=503, msg="打招呼次数检查失败，请稍后重试")

    if quota_status == "disabled":
        return Fail(code=403, msg="打招呼功能已关闭", data={"quota": quota})
    if quota_status == "cooldown":
        return Fail(code=429, msg="操作太频繁，请稍后再试", data={"quota": quota})
    if quota_status == "exhausted":
        return Fail(code=429, msg="今日打招呼次数已用完", data={"quota": quota})

    target_users = await _fetch_online_flirt_users(current_user, config)
    if not target_users:
        try:
            await release_greet_quota(redis, user_id=int(current_user.id))
            quota = await get_greet_quota(
                redis, user_id=int(current_user.id), daily_limit=int(config.greet_daily_limit)
            )
        except Exception:
            pass
        return Success(
            data={
                "slot_index": req_in.slot_index,
                "content": content,
                "target_count": 0,
                "sent_count": 0,
                "failed_count": 0,
                "text_dnd_failed_count": 0,
                "im_failed_count": 0,
                "quota": quota,
                "failure_samples": [],
            },
            msg="暂无在线可打招呼用户",
        )

    try:
        await set_greet_cooldown(
            redis,
            user_id=int(current_user.id),
            cooldown_seconds=int(config.greet_cooldown_seconds),
        )
        quota = await get_greet_quota(redis, user_id=int(current_user.id), daily_limit=int(config.greet_daily_limit))
    except Exception:
        pass

    background_tasks.add_task(
        _run_flirt_greet_send_task,
        sender_id=int(current_user.id),
        target_user_ids=[int(target_user.id) for target_user in target_users if not bool(target_user.text_dnd_enabled)],
        text_dnd_user_ids=[int(target_user.id) for target_user in target_users if bool(target_user.text_dnd_enabled)],
        content=content,
    )

    return Success(
        data={
            "started": True,
            "slot_index": req_in.slot_index,
            "content": content,
            "target_count": len(target_users),
            "sent_count": 0,
            "failed_count": 0,
            "text_dnd_failed_count": 0,
            "im_failed_count": 0,
            "quota": quota,
            "failure_samples": [],
        }
    )


async def _run_flirt_greet_send_task(
    *,
    sender_id: int,
    target_user_ids: list[int],
    text_dnd_user_ids: list[int],
    content: str,
) -> None:
    sent_count = 0
    im_failed_count = 0
    for target_id in target_user_ids:
        ok = await send_text_message(sender_id, target_id, content)
        if ok:
            sent_count += 1
        else:
            im_failed_count += 1

    logger.info(
        "flirt greet background send finished: sender_id={}, target_count={}, sent_count={}, text_dnd_failed_count={}, im_failed_count={}",
        sender_id,
        len(target_user_ids) + len(text_dnd_user_ids),
        sent_count,
        len(text_dnd_user_ids),
        im_failed_count,
    )
