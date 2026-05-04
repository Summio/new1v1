from datetime import datetime, timedelta
import asyncio

from fastapi import APIRouter, Depends

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.log import logger
from app.core.call_reject_protect import calc_left_seconds, should_block_rejected_call
from app.core.time_utils import now_local_naive, to_utc_aware
from app.models import AppUser, CallRecord
from app.services.call_trace_service import CallTraceService
from app.services.call_income_service import (
    get_anchor_share_bps,
    resolve_income_anchor_id,
    settle_call_anchor_income_once,
)
from app.schemas.app_api import (
    CallActionOut,
    CallActionIn,
    CallEndIn,
    CallEndOut,
    DialingIn,
    DialingOut,
)
from app.schemas.base import Fail, Success
from app.utils.media_url import to_relative_media_url
from app.utils.parse import safe_parse_int, clamp_int
from app.utils.billing import calc_due_minutes as _calc_due_minutes_with_free
from app.websocket import events as ws_events
from tortoise.expressions import F, Q
from tortoise.transactions import in_transaction

router = APIRouter()

CALL_RING_TIMEOUT_SECONDS = 30
DEFAULT_FREE_SECONDS_BEFORE_BILLING = 10
DEFAULT_REJECT_INBOUND_PROTECT_SECONDS = 5
DEFAULT_REJECT_PAIR_PROTECT_SECONDS = 5
MAX_REJECT_PROTECT_SECONDS = 600
MAX_FREE_SECONDS_BEFORE_BILLING = 600
DEFAULT_ANCHOR_SHARE_BPS = 5000

_call_trace_service = CallTraceService()


def _is_ring_timeout(call_record: CallRecord) -> bool:
    created_at = to_utc_aware(call_record.created_at)
    return to_utc_aware(now_local_naive()) - created_at > timedelta(seconds=CALL_RING_TIMEOUT_SECONDS)


async def _mark_timeout_if_needed(call_record: CallRecord) -> bool:
    if call_record.status == "pending" and _is_ring_timeout(call_record):
        call_record.status = "ended"
        call_record.end_reason = "timeout"
        call_record.ended_at = now_local_naive()
        call_record.effective_ended_at = call_record.ended_at
        call_record.end_basis = "timeout"
        call_record.force_exit_user_id = None
        await call_record.save()
        await _append_call_trace(
            call_record,
            phase="timeout",
            actor_user_id=int(call_record.caller_id),
            reason="timeout",
        )
        return True
    return False


async def _append_call_trace(
    call_record: CallRecord,
    *,
    phase: str,
    actor_user_id: int,
    reason: str | None = None,
) -> None:
    # 留痕失败不影响通话主流程
    await _call_trace_service.append(
        call_record=call_record,
        phase=phase,
        actor_user_id=actor_user_id,
        reason=reason,
    )




async def _get_reject_inbound_protect_seconds() -> int:
    from app.models.system_config import SystemConfig

    raw = await SystemConfig.get_value(
        "call_reject_inbound_protect_seconds",
        str(DEFAULT_REJECT_INBOUND_PROTECT_SECONDS),
    )
    seconds = safe_parse_int(raw, DEFAULT_REJECT_INBOUND_PROTECT_SECONDS)
    return clamp_int(seconds, 0, MAX_REJECT_PROTECT_SECONDS)


async def _get_reject_pair_protect_seconds() -> int:
    from app.models.system_config import SystemConfig

    raw = await SystemConfig.get_value(
        "call_reject_pair_protect_seconds",
        str(DEFAULT_REJECT_PAIR_PROTECT_SECONDS),
    )
    seconds = safe_parse_int(raw, DEFAULT_REJECT_PAIR_PROTECT_SECONDS)
    return clamp_int(seconds, 0, MAX_REJECT_PROTECT_SECONDS)


def _calc_duration_seconds(call_record: CallRecord) -> int:
    if call_record.status != "ongoing" or not call_record.connected_at:
        return max(0, int(call_record.duration or 0))
    elapsed = (to_utc_aware(now_local_naive()) - to_utc_aware(call_record.connected_at)).total_seconds()
    return max(0, int(elapsed))


async def _get_free_seconds_before_billing() -> int:
    from app.models.system_config import SystemConfig

    raw = await SystemConfig.get_value(
        "call_billing_free_seconds",
        str(DEFAULT_FREE_SECONDS_BEFORE_BILLING),
    )
    seconds = safe_parse_int(raw, DEFAULT_FREE_SECONDS_BEFORE_BILLING)
    return clamp_int(seconds, 0, MAX_FREE_SECONDS_BEFORE_BILLING)




async def _resolve_payer_id(call_record: CallRecord) -> int:
    """
    视频通话扣费方规则：非主播方永远付费。
    - 主播（无论主叫还是被叫）不扣费
    - 非主播用户（无论主叫还是被叫）付费
    - 双方都不是主播：主叫方付费（caller_id）
    B-2 修复：使用 select_for_update 加行锁，防止在检查期间 anchor 被审批/取消时出现 TOCTOU
    """
    caller_id = int(call_record.caller_id)
    callee_id = int(call_record.callee_id)

    # 单次 IN 查询 + FOR UPDATE，避免并发状态变化导致 TOCTOU
    users = {
        int(u.id): bool(u.is_anchor)
        for u in await AppUser.filter(id__in=[caller_id, callee_id]).select_for_update().all()
    }
    caller_is_anchor = users.get(caller_id, False)
    callee_is_anchor = users.get(callee_id, False)

    # 主播不承担通话费用
    if caller_is_anchor and not callee_is_anchor:
        # 主播是主叫，非主播是被叫 → 被叫付费
        return callee_id
    if callee_is_anchor and not caller_is_anchor:
        # 主播是被叫，非主播是主叫 → 主叫付费
        return caller_id

    # 双方都是主播 → 不计费，返回 0（与 watchdog 规则一致）
    return 0


def _resolve_billing_free_seconds(call_record: CallRecord, default_seconds: int) -> int:
    snapshot_seconds = getattr(call_record, "billing_free_seconds", None)
    if snapshot_seconds is None:
        return max(0, int(default_seconds))
    return max(0, int(snapshot_seconds))


async def _resolve_payer_id_with_snapshot(call_record: CallRecord) -> int:
    snapshot_payer_id = getattr(call_record, "payer_user_id", None)
    if snapshot_payer_id is not None:
        return int(snapshot_payer_id)
    return await _resolve_payer_id(call_record)


@router.post("/dialing", summary="发起呼叫(余额预检)", dependencies=[Depends(DependAppAuth)])
async def dialing(req_in: DialingIn):
    caller_id = CTX_APP_USER_ID.get()
    app_user: AppUser = CTX_APP_USER_OBJ.get()
    reject_inbound_protect_seconds = await _get_reject_inbound_protect_seconds()
    reject_pair_protect_seconds = await _get_reject_pair_protect_seconds()

    anchor_user_id = int(req_in.anchor_user_id or 0)
    if anchor_user_id <= 0:
        return Fail(code=400, msg="主播参数错误")

    # anchor_user_id 直接使用 app_user.id
    anchor_user = await AppUser.filter(
        id=anchor_user_id,
        is_anchor=True,
        status="normal",
    ).first()
    if not anchor_user:
        return Fail(code=404, msg="主播不存在或未认证")

    # 禁止自呼叫
    if caller_id == anchor_user.id:
        return Fail(code=400, msg="不能呼叫自己")

    # 使用 Redis 在线状态检查（WebSocket 方式）
    from app.websocket.presence import is_online as check_anchor_online
    if not await check_anchor_online(anchor_user.id):
        return Fail(code=400, msg="主播当前不在线，请稍后再试")

    call_price = int(anchor_user.anchor_call_price or 0)

    # 只做余额门槛检查，不预扣（视频通话消耗金币）
    if app_user.coins < call_price:
        return Fail(code=501, msg="余额不足，请先充值")

    # 事务包裹忙线检查 + 记录创建：防止 TOCTOU 竞态
    async with in_transaction() as conn:
        # 加行锁：锁住主叫和被叫用户行，防止并发创建冲突的通话记录
        await AppUser.filter(id=caller_id).using_db(conn).select_for_update().first()
        await AppUser.filter(id=anchor_user.id).using_db(conn).select_for_update().first()

        # 主叫忙线检测
        caller_busy = (
            await CallRecord.filter(
                (Q(caller_id=caller_id) | Q(callee_id=caller_id)),
                status__in=["pending", "ongoing"],
            )
            .using_db(conn)
            .exists()
        )
        if caller_busy:
            return Fail(code=409, msg="你正在通话中，请先结束当前通话")

        # 被叫忙线检测
        callee_busy = (
            await CallRecord.filter(
                callee_id=anchor_user.id,
                status__in=["pending", "ongoing"],
            )
            .using_db(conn)
            .exists()
        )
        if callee_busy:
            return Fail(code=409, msg="对方忙线中，请稍后再试")

        # L-4 修复：检查 protect 窗口内的所有记录，而非仅最近一条
        if reject_inbound_protect_seconds > 0:
            protect_since_inbound = now_local_naive() - timedelta(seconds=reject_inbound_protect_seconds)
            all_rejected_for_callee = (
                await CallRecord.filter(
                    callee_id=anchor_user.id,
                    status="ended",
                    end_reason="rejected",
                    updated_at__gte=protect_since_inbound,
                )
                .using_db(conn)
                .order_by("-updated_at")
                .all()
            )
            for r in all_rejected_for_callee:
                if should_block_rejected_call(r.updated_at, reject_inbound_protect_seconds):
                    left = calc_left_seconds(r.updated_at, reject_inbound_protect_seconds)
                    return Fail(code=429, msg=f"对方暂不接听，请{left}秒后再试")

        if reject_pair_protect_seconds > 0:
            protect_since_pair = now_local_naive() - timedelta(seconds=reject_pair_protect_seconds)
            all_rejected_for_pair = (
                await CallRecord.filter(
                    caller_id=caller_id,
                    callee_id=anchor_user.id,
                    status="ended",
                    end_reason="rejected",
                    updated_at__gte=protect_since_pair,
                )
                .using_db(conn)
                .order_by("-updated_at")
                .all()
            )
            for r in all_rejected_for_pair:
                if should_block_rejected_call(r.updated_at, reject_pair_protect_seconds):
                    left = calc_left_seconds(r.updated_at, reject_pair_protect_seconds)
                    return Fail(code=429, msg=f"你刚被对方拒绝，请{left}秒后再呼叫")

        # 创建通话记录（同一事务内，锁已持有，无竞争）
        anchor_share_bps = await get_anchor_share_bps()
        income_anchor_user_id = int(anchor_user.id) if not bool(app_user.is_anchor) else None
        call_record = await CallRecord.create(
            caller_id=caller_id,
            callee_id=anchor_user.id,
            call_price=call_price,
            status="pending",
            income_anchor_user_id=income_anchor_user_id,
            anchor_share_bps=anchor_share_bps,
            using_db=conn,
        )

    # 事务结束后查询被叫信息（不在锁内执行，减少锁持有时间）
    callee_user = await AppUser.filter(id=anchor_user.id).first()
    callee_nickname = (
        (callee_user.nickname or callee_user.username or f"用户{anchor_user.id}")
        if callee_user
        else f"用户{anchor_user.id}"
    )
    callee_avatar = to_relative_media_url(callee_user.avatar) if callee_user else None
    await _append_call_trace(
        call_record,
        phase="dialing",
        actor_user_id=int(caller_id),
    )
    # 推送 WebSocket 来电通知给被叫方（fire-and-forget）
    asyncio.create_task(_ws_push_call_incoming(
        callee_id=int(anchor_user.id),
        call_id=int(call_record.id),
        caller_id=int(caller_id),
        caller_name=app_user.nickname or f"用户{caller_id}",
        caller_avatar=to_relative_media_url(app_user.avatar),
        call_price=int(call_price or 0),
        left_seconds=CALL_RING_TIMEOUT_SECONDS,
    ))

    return Success(
        data=DialingOut(
            call_id=call_record.id,
            coins=app_user.coins,
            can_call=True,
            callee_id=int(anchor_user.id),
            callee_nickname=callee_nickname,
            callee_avatar=callee_avatar,
            call_price=int(call_price or 0),
            ring_timeout_seconds=CALL_RING_TIMEOUT_SECONDS,
            left_seconds=CALL_RING_TIMEOUT_SECONDS,
            msg="呼叫已发出，等待接听",
        ).model_dump()
    )


@router.post("/call/accept", summary="接听通话", dependencies=[Depends(DependAppAuth)])
async def accept_call(req_in: CallActionIn):
    user_id = CTX_APP_USER_ID.get()

    # 事务包裹 + SELECT FOR UPDATE：防止并发接听导致多重计费
    async with in_transaction() as conn:
        call_record = (
            await CallRecord.filter(id=req_in.call_id)
            .using_db(conn)
            .select_for_update()
            .first()
        )
        if not call_record:
            return Fail(code=404, msg="通话不存在")

        if int(call_record.callee_id) != int(user_id):
            return Fail(code=403, msg="仅被叫方可接听")

        if await _mark_timeout_if_needed(call_record):
            return Fail(code=400, msg="来电已超时")

        if call_record.status != "pending":
            return Fail(code=400, msg="通话状态不可接听")

        # 被叫忙线保护：除当前来电外，如果还存在 ongoing，则拒绝接听
        has_other_ongoing = (
            await CallRecord.filter(callee_id=user_id, status="ongoing")
            .using_db(conn)
            .exclude(id=call_record.id)
            .exists()
        )
        if has_other_ongoing:
            return Fail(code=409, msg="你正在其他通话中")

        # 主叫忙线检查：防止主叫同时呼出多条
        caller_has_ongoing = (
            await CallRecord.filter(caller_id=int(call_record.caller_id), status="ongoing")
            .using_db(conn)
            .exclude(id=call_record.id)
            .exists()
        )
        if caller_has_ongoing:
            return Fail(code=409, msg="对方正在其他通话中")

        call_record.status = "ongoing"
        call_record.end_reason = None
        call_record.connected_at = now_local_naive()
        call_record.duration = 0
        call_record.deducted_amount = 0
        call_record.deducted_minutes = 0
        call_record.last_renew_at = None
        call_record.billing_free_seconds = await _get_free_seconds_before_billing()
        call_record.payer_user_id = await _resolve_payer_id(call_record)
        call_record.ended_at = None
        call_record.effective_ended_at = None
        call_record.end_basis = None
        call_record.force_exit_user_id = None
        await call_record.save(using_db=conn)
        await _append_call_trace(
            call_record,
            phase="accepted",
            actor_user_id=int(user_id),
        )
        # 推送 WebSocket 事件给主叫方（fire-and-forget）
        asyncio.create_task(_ws_push_call_accepted(
            caller_id=int(call_record.caller_id),
            call_id=int(call_record.id),
        ))

    return Success(
        data=CallActionOut(next_status="ongoing", msg="已接听").model_dump(),
        msg="已接听",
    )


@router.post("/call/reject", summary="拒绝通话", dependencies=[Depends(DependAppAuth)])
async def reject_call(req_in: CallActionIn):
    user_id = CTX_APP_USER_ID.get()

    async with in_transaction() as conn:
        call_record = (
            await CallRecord.filter(id=req_in.call_id)
            .using_db(conn)
            .select_for_update()
            .first()
        )
        if not call_record:
            return Fail(code=404, msg="通话不存在")

        if int(call_record.callee_id) != int(user_id):
            return Fail(code=403, msg="仅被叫方可拒绝")

        if call_record.status != "pending":
            return Fail(code=400, msg="通话状态不可拒绝")

        call_record.status = "ended"
        call_record.end_reason = "rejected"
        call_record.ended_at = now_local_naive()
        call_record.effective_ended_at = call_record.ended_at
        call_record.end_basis = "manual_end"
        call_record.force_exit_user_id = None
        await call_record.save(using_db=conn)
        await _append_call_trace(
            call_record,
            phase="rejected",
            actor_user_id=int(user_id),
            reason="rejected",
        )
        # 推送 WebSocket 事件给主叫方（fire-and-forget）
        asyncio.create_task(_ws_push_call_rejected(
            caller_id=int(call_record.caller_id),
            call_id=int(call_record.id),
            reason="rejected",
        ))

    return Success(
        data=CallActionOut(next_status="ended", msg="已拒绝").model_dump(),
        msg="已拒绝",
    )


@router.post("/call/cancel", summary="取消呼叫", dependencies=[Depends(DependAppAuth)])
async def cancel_call(req_in: CallActionIn):
    user_id = CTX_APP_USER_ID.get()

    async with in_transaction() as conn:
        call_record = (
            await CallRecord.filter(id=req_in.call_id)
            .using_db(conn)
            .select_for_update()
            .first()
        )
        if not call_record:
            return Fail(code=404, msg="通话不存在")

        if int(call_record.caller_id) != int(user_id):
            return Fail(code=403, msg="仅主叫方可取消")

        if call_record.status != "pending":
            return Fail(code=400, msg="通话状态不可取消")

        call_record.status = "ended"
        call_record.end_reason = "cancelled"
        call_record.ended_at = now_local_naive()
        call_record.effective_ended_at = call_record.ended_at
        call_record.end_basis = "manual_end"
        call_record.force_exit_user_id = None
        await call_record.save(using_db=conn)
        await _append_call_trace(
            call_record,
            phase="cancelled",
            actor_user_id=int(user_id),
            reason="cancelled",
        )
        # 推送 WebSocket 事件给被叫方（fire-and-forget）
        asyncio.create_task(_ws_push_call_cancelled(
            callee_id=int(call_record.callee_id),
            call_id=int(call_record.id),
            reason="cancelled",
        ))

    return Success(
        data=CallActionOut(next_status="ended", msg="已取消呼叫").model_dump(),
        msg="已取消呼叫",
    )


@router.post("/call/end", summary="通话结束结算", dependencies=[Depends(DependAppAuth)])
async def call_end(req_in: CallEndIn):
    user_id = CTX_APP_USER_ID.get()

    # 用于事务结束后推送余额更新
    _payer_id_for_balance_push: int | None = None
    _anchor_id_for_balance_push: int | None = None
    _balance_changed_for_push = False

    async with in_transaction() as conn:
        call_record = (
            await CallRecord.filter(id=req_in.call_id)
            .using_db(conn)
            .select_for_update()
            .first()
        )
        if not call_record:
            return Fail(code=404, msg="通话不存在或已结束")

        if user_id not in {int(call_record.caller_id), int(call_record.callee_id)}:
            return Fail(code=403, msg="无权结束该通话")

        # B-3 修复：SELECT FOR UPDATE 后必须重新检查状态，
        # 防止 watchdog 已在并发事务中关闭同一通话导致双重退款
        if call_record.status == "ended":
            # 已由 watchdog 或另一方结束，无需重复处理
            pass
        else:
            duration_seconds = _calc_duration_seconds(call_record)
            call_record.duration = duration_seconds
            free_seconds_before_billing = _resolve_billing_free_seconds(
                call_record,
                await _get_free_seconds_before_billing(),
            )
            due_minutes = (
                _calc_due_minutes_with_free(duration_seconds, free_seconds_before_billing)
                if call_record.status == "ongoing"
                else 0
            )
            actual_fee = due_minutes * int(call_record.call_price or 0)
            deducted_amount = int(call_record.deducted_amount or 0)
            charged_amount = deducted_amount

            # P0-3 修复：金额守恒下限校验，防止 deducted_amount 异常时 total_fee 为负
            if charged_amount < 0:
                logger.error(
                    "call_end charged_amount negative: call_id={} deducted_amount={} actual_fee={}",
                    call_record.id,
                    deducted_amount,
                    actual_fee,
                )
                charged_amount = 0

            payer_id = await _resolve_payer_id_with_snapshot(call_record)
            participants = await AppUser.filter(
                id__in=[int(call_record.caller_id), int(call_record.callee_id)]
            ).using_db(conn).all()
            if not getattr(call_record, "income_anchor_user_id", None):
                call_record.income_anchor_user_id = (
                    resolve_income_anchor_id(participants, payer_id) or None
                )

            if actual_fee > deducted_amount and payer_id > 0:
                top_up_amount = actual_fee - deducted_amount
                await AppUser.filter(id=payer_id).using_db(conn).select_for_update().first()
                updated = await AppUser.filter(
                    id=payer_id,
                    coins__gte=top_up_amount,
                ).using_db(conn).update(
                    coins=F("coins") - top_up_amount
                )
                if updated > 0:
                    charged_amount += top_up_amount
                    _payer_id_for_balance_push = payer_id
                    _balance_changed_for_push = True
                else:
                    call_record.end_reason = "balance_empty"
                    logger.warning(
                        "call_end top-up failed by insufficient balance: call_id={} payer_id={} required={} deducted={} actual_fee={}",
                        call_record.id,
                        payer_id,
                        top_up_amount,
                        deducted_amount,
                        actual_fee,
                    )

            if actual_fee < deducted_amount and payer_id > 0:
                refund_amount = deducted_amount - actual_fee
                # 加行锁：防止并发退款导致重复到账
                await AppUser.filter(id=payer_id).using_db(conn).select_for_update().first()
                await AppUser.filter(id=payer_id).using_db(conn).update(
                    coins=F("coins") + refund_amount
                )
                charged_amount -= refund_amount
                _payer_id_for_balance_push = payer_id
                _balance_changed_for_push = True

            call_record.deducted_minutes = due_minutes
            call_record.deducted_amount = charged_amount
            call_record.total_fee = charged_amount
            call_record.status = "ended"
            call_record.end_reason = call_record.end_reason or "normal"
            call_record.ended_at = now_local_naive()
            call_record.effective_ended_at = call_record.ended_at
            call_record.end_basis = "manual_end"
            call_record.force_exit_user_id = None
            settlement = await settle_call_anchor_income_once(
                call_record=call_record,
                conn=conn,
                total_fee=charged_amount,
                payer_id=payer_id,
                participants=participants,
            )
            if settlement.settled and settlement.anchor_user_id > 0:
                _anchor_id_for_balance_push = settlement.anchor_user_id
            await call_record.save(using_db=conn)

            await _append_call_trace(
                call_record,
                phase="ended",
                actor_user_id=int(user_id),
                reason=call_record.end_reason,
            )
            # W-2 修复：仅在本地处理结束流程时通知对方，避免 watchdog 已推送后重复推送
            peer_id = (
                int(call_record.callee_id)
                if int(user_id) == int(call_record.caller_id)
                else int(call_record.caller_id)
            )
            asyncio.create_task(_ws_push_call_ended_to_peer(
                peer_id=peer_id,
                caller_id=int(call_record.caller_id),
                callee_id=int(call_record.callee_id),
                call_id=int(call_record.id),
                end_reason=call_record.end_reason,
            ))

        user = await AppUser.filter(id=user_id).using_db(conn).first()
        final_coins = user.coins if user else 0

    # 事务结束后，如余额发生变化则推送余额更新给付费方
    if _payer_id_for_balance_push is not None and _balance_changed_for_push:
        asyncio.create_task(_ws_push_balance_updated(
            payer_id=_payer_id_for_balance_push,
        ))
    if _anchor_id_for_balance_push is not None:
        asyncio.create_task(_ws_push_balance_updated(
            payer_id=_anchor_id_for_balance_push,
        ))

    return Success(
        data=CallEndOut(
            total_fee=int(call_record.total_fee or 0),
            coins=final_coins,
            duration=int(call_record.duration or 0),
            next_status="ended",
            msg="通话已结束",
        ).model_dump()
    )


# ===== WebSocket 推送辅助函数（fire-and-forget） =====

async def _ws_push_call_incoming(
    callee_id: int,
    call_id: int,
    caller_id: int,
    caller_name: str,
    caller_avatar: str | None,
    call_price: int,
    left_seconds: int,
) -> None:
    try:
        await ws_events.push_call_incoming(
            callee_id=callee_id,
            call_id=call_id,
            caller_id=caller_id,
            caller_name=caller_name,
            caller_avatar=caller_avatar,
            call_price=call_price,
            left_seconds=left_seconds,
        )
    except Exception:  # noqa: BLE001
        pass  # 静默忽略，不影响主流程


async def _ws_push_call_accepted(caller_id: int, call_id: int) -> None:
    try:
        await ws_events.push_call_accepted(caller_id=caller_id, call_id=call_id)
    except Exception:  # noqa: BLE001
        pass


async def _ws_push_call_rejected(caller_id: int, call_id: int, reason: str | None = None) -> None:
    try:
        await ws_events.push_call_rejected(caller_id=caller_id, call_id=call_id, reason=reason)
    except Exception:  # noqa: BLE001
        pass


async def _ws_push_call_cancelled(callee_id: int, call_id: int, reason: str | None = None) -> None:
    try:
        await ws_events.push_call_cancelled(callee_id=callee_id, call_id=call_id, reason=reason)
    except Exception:  # noqa: BLE001
        pass


async def _ws_push_call_ended(
    caller_id: int,
    callee_id: int,
    call_id: int,
    end_reason: str | None = None,
) -> None:
    try:
        await ws_events.push_call_ended(
            caller_id=caller_id,
            callee_id=callee_id,
            call_id=call_id,
            end_reason=end_reason,
        )
    except Exception:  # noqa: BLE001
        pass


async def _ws_push_call_ended_to_peer(
    peer_id: int,
    caller_id: int,
    callee_id: int,
    call_id: int,
    end_reason: str | None = None,
) -> None:
    try:
        from app.websocket.manager import get_manager

        await get_manager().push_to_user(
            user_id=peer_id,
            event="call_ended",
            data={
                "call_id": call_id,
                "caller_id": caller_id,
                "callee_id": callee_id,
                "end_reason": end_reason,
                "ts": int(datetime.now().timestamp()),
            },
            critical=True,
        )
    except Exception:  # noqa: BLE001
        pass


async def _ws_push_balance_updated(payer_id: int) -> None:
    """通话结束后推送退款后的余额给付费方（fire-and-forget）。"""
    try:
        from app.models import AppUser

        payer = await AppUser.filter(id=payer_id).first()
        if payer:
            await ws_events.push_balance_update(
                user_id=payer_id,
                coins=payer.coins,
                diamonds=payer.diamonds,
            )
    except Exception:  # noqa: BLE001
        pass
