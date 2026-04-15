from fastapi import APIRouter, Depends

from app.core.app_auth import DependAppAuth
from app.core.dependency import LimitHeartbeat
from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.core.redis import RedisCache, heartbeat_key, get_redis
from app.models import Anchor, AppUser, CallRecord
from app.schemas.app_api import (
    CallEndIn,
    CallEndOut,
    DialingIn,
    DialingOut,
    HeartbeatIn,
    HeartbeatOut,
)
from app.schemas.base import Fail, Success
from app.settings import settings

router = APIRouter()

HEARTBEAT_INTERVAL = settings.HEARTBEAT_INTERVAL  # 从配置读取，默认 5 秒


@router.post("/dialing", summary="发起呼叫(余额预检)", dependencies=[DependAppAuth])
async def dialing(req_in: DialingIn):
    caller_id = CTX_APP_USER_ID.get()
    app_user: AppUser = CTX_APP_USER_OBJ.get()

    # 检查主播是否存在且在线（需审批通过）
    anchor = await Anchor.filter(
        id=req_in.anchor_id, is_online=True, apply_status="approved"
    ).first()
    if not anchor:
        return Fail(code=404, msg="主播不在线或不存在")

    call_price = anchor.call_price

    # 只做余额门槛检查，不预扣（heartbeat 时开始正常计费）
    if app_user.diamonds < call_price:
        return Fail(code=501, msg="余额不足，请先充值")

    # 创建通话记录（含通话价格，固定以发起时价格计费）
    call_record = await CallRecord.create(
        caller_id=caller_id,
        callee_id=anchor.app_user_id,
        call_price=call_price,
        status="ongoing",
    )

    # 在 Redis 中记录心跳 key（15秒 TTL，掉线自动过期）
    redis = await get_redis()
    cache = RedisCache(redis)
    await cache.set(heartbeat_key(call_record.id), 1, expire=HEARTBEAT_INTERVAL * 3)

    return Success(
        data=DialingOut(
            call_id=call_record.id,
            diamonds=app_user.diamonds,
            can_call=True,
            msg="可以呼叫",
        ).model_dump()
    )


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

    call_record = await CallRecord.filter(id=req_in.call_id, status="ongoing").first()
    if not call_record:
        return Success(data=CallEndOut(total_fee=0, diamonds=0, duration=0, msg="通话已结束").model_dump())

    redis = await get_redis()
    cache = RedisCache(redis)

    # 获取最终钻石余额（心跳已直接更新 DB，从 DB 读取）
    app_user = await AppUser.filter(id=caller_id).first()
    final_diamonds = app_user.diamonds if app_user else 0

    # 计算总费用（使用通话记录中的固定单价，与心跳扣费一致）
    if call_record.duration > 0:
        call_price = call_record.call_price
        fee_per_tick = call_price // 12
        ticks = (call_record.duration + HEARTBEAT_INTERVAL - 1) // HEARTBEAT_INTERVAL
        total_fee = ticks * fee_per_tick
    else:
        total_fee = 0

    call_record.status = "ended"
    call_record.end_reason = "normal"
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
