from datetime import datetime, timedelta, timezone
import math

from fastapi import APIRouter, Depends

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.core.dependency import LimitHeartbeat
from app.core.redis import RedisCache, get_redis, heartbeat_key
from app.models import Anchor, AppUser, CallRecord
from app.schemas.app_api import (
    CallActionIn,
    CallEndIn,
    CallEndOut,
    CallStatusOut,
    DialingIn,
    DialingOut,
    HeartbeatIn,
    HeartbeatOut,
    IncomingCallOut,
)
from app.schemas.base import Fail, Success
from app.settings import settings
from tortoise.expressions import Q

router = APIRouter()

HEARTBEAT_INTERVAL = settings.HEARTBEAT_INTERVAL  # 从配置读取，默认 5 秒
CALL_RING_TIMEOUT_SECONDS = 30
DEFAULT_REJECT_INBOUND_PROTECT_SECONDS = 5
DEFAULT_REJECT_PAIR_PROTECT_SECONDS = 5
MAX_REJECT_PROTECT_SECONDS = 600


def _to_aware(dt: datetime | None) -> datetime:
    if dt is None:
        return datetime.now(timezone.utc)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _is_ring_timeout(call_record: CallRecord) -> bool:
    created_at = _to_aware(call_record.created_at)
    return datetime.now(timezone.utc) - created_at > timedelta(seconds=CALL_RING_TIMEOUT_SECONDS)


async def _mark_timeout_if_needed(call_record: CallRecord) -> bool:
    if call_record.status == "pending" and _is_ring_timeout(call_record):
        call_record.status = "ended"
        call_record.end_reason = "timeout"
        await call_record.save()
        return True
    return False


def _safe_parse_int(raw: str | None, default: int) -> int:
    if raw is None:
        return default
    try:
        return int(str(raw).strip())
    except (TypeError, ValueError):
        return default


async def _get_reject_inbound_protect_seconds() -> int:
    from app.models.system_config import SystemConfig

    raw = await SystemConfig.get_value(
        "call_reject_inbound_protect_seconds",
        str(DEFAULT_REJECT_INBOUND_PROTECT_SECONDS),
    )
    seconds = _safe_parse_int(raw, DEFAULT_REJECT_INBOUND_PROTECT_SECONDS)
    if seconds < 0:
        return 0
    if seconds > MAX_REJECT_PROTECT_SECONDS:
        return MAX_REJECT_PROTECT_SECONDS
    return seconds


async def _get_reject_pair_protect_seconds() -> int:
    from app.models.system_config import SystemConfig

    raw = await SystemConfig.get_value(
        "call_reject_pair_protect_seconds",
        str(DEFAULT_REJECT_PAIR_PROTECT_SECONDS),
    )
    seconds = _safe_parse_int(raw, DEFAULT_REJECT_PAIR_PROTECT_SECONDS)
    if seconds < 0:
        return 0
    if seconds > MAX_REJECT_PROTECT_SECONDS:
        return MAX_REJECT_PROTECT_SECONDS
    return seconds


def _left_seconds(event_time: datetime | None, protect_seconds: int) -> int:
    if event_time is None or protect_seconds <= 0:
        return 0
    elapsed = (datetime.now(timezone.utc) - _to_aware(event_time)).total_seconds()
    left = protect_seconds - elapsed
    return max(0, math.ceil(left))


@router.post("/dialing", summary="发起呼叫(余额预检)", dependencies=[DependAppAuth])
async def dialing(req_in: DialingIn):
    caller_id = CTX_APP_USER_ID.get()
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    reject_inbound_protect_seconds = await _get_reject_inbound_protect_seconds()
    reject_pair_protect_seconds = await _get_reject_pair_protect_seconds()

    # 主叫忙线检测：若自己已有 pending/ongoing 通话，不允许再次发起
    caller_busy = await CallRecord.filter(
        (Q(caller_id=caller_id) | Q(callee_id=caller_id)),
        status__in=["pending", "ongoing"],
    ).exists()
    if caller_busy:
        return Fail(code=409, msg="你正在通话中，请先结束当前通话")

    # 检查主播是否存在且在线（需审批通过）
    anchor = await Anchor.filter(
        id=req_in.anchor_id, is_online=True, apply_status="approved"
    ).first()
    if not anchor:
        return Fail(code=404, msg="主播不在线或不存在")

    # 被叫忙线检测：目标主播已有 pending/ongoing 通话，返回忙线
    callee_busy = await CallRecord.filter(
        callee_id=anchor.app_user_id,
        status__in=["pending", "ongoing"],
    ).exists()
    if callee_busy:
        return Fail(code=409, msg="对方忙线中，请稍后再试")

    if reject_inbound_protect_seconds > 0:
        protect_since_inbound = datetime.now(timezone.utc) - timedelta(seconds=reject_inbound_protect_seconds)
        # 规则1：被叫在保护期内拒绝过任意来电，则禁止新的呼入
        latest_rejected_for_callee = (
            await CallRecord.filter(
                callee_id=anchor.app_user_id,
                status="ended",
                end_reason="rejected",
                updated_at__gte=protect_since_inbound,
            )
            .order_by("-updated_at")
            .first()
        )
        if latest_rejected_for_callee:
            left = _left_seconds(latest_rejected_for_callee.updated_at, reject_inbound_protect_seconds)
            return Fail(code=429, msg=f"对方暂不接听，请{left}秒后再试")

    if reject_pair_protect_seconds > 0:
        protect_since_pair = datetime.now(timezone.utc) - timedelta(seconds=reject_pair_protect_seconds)
        # 规则2：同一主叫-被叫对在保护期内被拒绝，禁止再次呼叫同一用户
        latest_rejected_for_pair = (
            await CallRecord.filter(
                caller_id=caller_id,
                callee_id=anchor.app_user_id,
                status="ended",
                end_reason="rejected",
                updated_at__gte=protect_since_pair,
            )
            .order_by("-updated_at")
            .first()
        )
        if latest_rejected_for_pair:
            left = _left_seconds(latest_rejected_for_pair.updated_at, reject_pair_protect_seconds)
            return Fail(code=429, msg=f"你刚被对方拒绝，请{left}秒后再呼叫")

    call_price = anchor.call_price

    # 只做余额门槛检查，不预扣
    if app_user.diamonds < call_price:
        return Fail(code=501, msg="余额不足，请先充值")

    # 创建通话记录（先 pending，待主播接听）
    call_record = await CallRecord.create(
        caller_id=caller_id,
        callee_id=anchor.app_user_id,
        call_price=call_price,
        status="pending",
    )

    return Success(
        data=DialingOut(
            call_id=call_record.id,
            diamonds=app_user.diamonds,
            can_call=True,
            msg="呼叫已发出，等待接听",
        ).model_dump()
    )


@router.get("/call/incoming", summary="查询当前主播来电", dependencies=[DependAppAuth])
async def incoming_call():
    user_id = CTX_APP_USER_ID.get()

    call_record = (
        await CallRecord.filter(callee_id=user_id, status="pending").order_by("-id").first()
    )
    if not call_record:
        return Success(data=None)

    if await _mark_timeout_if_needed(call_record):
        return Success(data=None)

    caller = await AppUser.filter(id=call_record.caller_id).first()
    nickname = (caller.nickname or f"用户{call_record.caller_id}") if caller else f"用户{call_record.caller_id}"
    avatar = caller.avatar if caller else ""

    return Success(
        data=IncomingCallOut(
            call_id=call_record.id,
            caller_id=int(call_record.caller_id),
            caller_nickname=nickname,
            caller_avatar=avatar,
            created_at=_to_aware(call_record.created_at).isoformat(),
        ).model_dump()
    )


@router.get("/call/status", summary="查询通话状态", dependencies=[DependAppAuth])
async def call_status(call_id: int):
    user_id = CTX_APP_USER_ID.get()

    call_record = await CallRecord.filter(id=call_id).first()
    if not call_record:
        return Fail(code=404, msg="通话不存在")

    if user_id not in {int(call_record.caller_id), int(call_record.callee_id)}:
        return Fail(code=403, msg="无权查看该通话")

    await _mark_timeout_if_needed(call_record)
    await call_record.refresh_from_db()

    return Success(
        data=CallStatusOut(
            call_id=call_record.id,
            caller_id=int(call_record.caller_id),
            callee_id=int(call_record.callee_id),
            status=call_record.status,
            created_at=_to_aware(call_record.created_at).isoformat() if call_record.created_at else None,
            end_reason=call_record.end_reason,
            duration=call_record.duration,
        ).model_dump()
    )


@router.post("/call/accept", summary="接听通话", dependencies=[DependAppAuth])
async def accept_call(req_in: CallActionIn):
    user_id = CTX_APP_USER_ID.get()

    call_record = await CallRecord.filter(id=req_in.call_id).first()
    if not call_record:
        return Fail(code=404, msg="通话不存在")

    if int(call_record.callee_id) != int(user_id):
        return Fail(code=403, msg="仅被叫方可接听")

    if await _mark_timeout_if_needed(call_record):
        return Fail(code=400, msg="来电已超时")

    if call_record.status != "pending":
        return Fail(code=400, msg="通话状态不可接听")

    # 被叫忙线保护：除当前来电外，如果还存在 ongoing，则拒绝接听
    has_other_ongoing = await CallRecord.filter(
        callee_id=user_id,
        status="ongoing",
    ).exclude(id=call_record.id).exists()
    if has_other_ongoing:
        return Fail(code=409, msg="你正在其他通话中")

    call_record.status = "ongoing"
    call_record.end_reason = None
    await call_record.save()

    redis = await get_redis()
    cache = RedisCache(redis)
    await cache.set(heartbeat_key(call_record.id), 1, expire=HEARTBEAT_INTERVAL * 3)

    return Success(msg="已接听")


@router.post("/call/reject", summary="拒绝通话", dependencies=[DependAppAuth])
async def reject_call(req_in: CallActionIn):
    user_id = CTX_APP_USER_ID.get()

    call_record = await CallRecord.filter(id=req_in.call_id).first()
    if not call_record:
        return Fail(code=404, msg="通话不存在")

    if int(call_record.callee_id) != int(user_id):
        return Fail(code=403, msg="仅被叫方可拒绝")

    if call_record.status != "pending":
        return Fail(code=400, msg="通话状态不可拒绝")

    call_record.status = "ended"
    call_record.end_reason = "rejected"
    await call_record.save()

    return Success(msg="已拒绝")


@router.post("/call/cancel", summary="取消呼叫", dependencies=[DependAppAuth])
async def cancel_call(req_in: CallActionIn):
    user_id = CTX_APP_USER_ID.get()

    call_record = await CallRecord.filter(id=req_in.call_id).first()
    if not call_record:
        return Fail(code=404, msg="通话不存在")

    if int(call_record.caller_id) != int(user_id):
        return Fail(code=403, msg="仅主叫方可取消")

    if call_record.status != "pending":
        return Fail(code=400, msg="通话状态不可取消")

    call_record.status = "ended"
    call_record.end_reason = "cancelled"
    await call_record.save()

    return Success(msg="已取消呼叫")


@router.post("/heartbeat", summary="通话心跳(每5秒)", dependencies=[DependAppAuth, Depends(LimitHeartbeat)])
async def heartbeat(req_in: HeartbeatIn):
    caller_id = CTX_APP_USER_ID.get()
    app_user: AppUser = CTX_APP_USER_OBJ.get()

    call_record = await CallRecord.filter(id=req_in.call_id, status="ongoing").first()
    if not call_record:
        return Fail(code=404, msg="通话不存在或已结束")

    redis = await get_redis()
    cache = RedisCache(redis)

    # 检查心跳是否还在（掉线检测）
    if not await cache.get(heartbeat_key(call_record.id)):
        call_record.status = "ended"
        call_record.end_reason = "timeout"
        await call_record.save()
        return Fail(code=400, msg="心跳超时，通话已结束")

    # 刷新心跳 TTL
    await cache.set(heartbeat_key(call_record.id), 1, expire=HEARTBEAT_INTERVAL * 3)

    # 使用通话记录中的固定单价（创建时锁定，防止主播中途调价导致计费不一致）
    call_price = call_record.call_price
    fee_per_tick = call_price // 12

    # 原子扣费（扣钻石）
    updated = await AppUser.filter(id=caller_id, diamonds__gte=fee_per_tick).update(
        diamonds=AppUser.diamonds - fee_per_tick
    )

    if updated == 0:
        call_record.status = "ended"
        call_record.end_reason = "balance_empty"
        await call_record.save()
        return Fail(code=501, msg="余额不足，通话结束")

    # 原子更新通话时长（防止并发心跳导致时长计算错误）
    await CallRecord.filter(id=call_record.id, status="ongoing").update(
        duration=CallRecord.duration + HEARTBEAT_INTERVAL
    )
    # 同步内存中的时长值（DB 已原子更新，内存值+1 即可）
    call_record.duration += HEARTBEAT_INTERVAL

    # 获取扣费后最新钻石余额
    updated_user = await AppUser.filter(id=caller_id).first()
    new_diamonds = updated_user.diamonds if updated_user else 0

    return Success(
        data=HeartbeatOut(
            diamonds=new_diamonds,
            duration=call_record.duration,
            msg="OK",
        ).model_dump()
    )


@router.post("/call/end", summary="通话结束结算", dependencies=[DependAppAuth])
async def call_end(req_in: CallEndIn):
    caller_id = CTX_APP_USER_ID.get()

    call_record = await CallRecord.filter(id=req_in.call_id).first()
    if not call_record:
        return Success(data=CallEndOut(total_fee=0, diamonds=0, duration=0, msg="通话已结束").model_dump())

    if caller_id not in {int(call_record.caller_id), int(call_record.callee_id)}:
        return Fail(code=403, msg="无权结束该通话")

    if call_record.status == "ended":
        app_user = await AppUser.filter(id=caller_id).first()
        final_diamonds = app_user.diamonds if app_user else 0
        return Success(
            data=CallEndOut(
                total_fee=call_record.total_fee,
                diamonds=final_diamonds,
                duration=call_record.duration,
                msg="通话已结束",
            ).model_dump()
        )

    redis = await get_redis()
    cache = RedisCache(redis)

    # 获取最终钻石余额（心跳已直接更新 DB，从 DB 读取）
    app_user = await AppUser.filter(id=caller_id).first()
    final_diamonds = app_user.diamonds if app_user else 0

    # 仅 ongoing 时进行计费结算，pending 直接为 0
    if call_record.status == "ongoing" and call_record.duration > 0:
        call_price = call_record.call_price
        fee_per_tick = call_price // 12
        ticks = (call_record.duration + HEARTBEAT_INTERVAL - 1) // HEARTBEAT_INTERVAL
        total_fee = ticks * fee_per_tick
    else:
        total_fee = 0

    call_record.status = "ended"
    call_record.end_reason = call_record.end_reason or "normal"
    call_record.total_fee = total_fee
    await call_record.save()

    await cache.delete(heartbeat_key(call_record.id))

    return Success(
        data=CallEndOut(
            total_fee=total_fee,
            diamonds=final_diamonds,
            duration=call_record.duration,
            msg="通话已结束",
        ).model_dump()
    )
