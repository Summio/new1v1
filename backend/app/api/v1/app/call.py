from datetime import datetime, timedelta, timezone

from fastapi import APIRouter

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.core.call_reject_protect import calc_left_seconds, should_block_rejected_call
from app.core.time_utils import now_local_naive, to_utc_aware
from app.models import Anchor, AppUser, CallRecord
from app.services.call_trace_service import CallTraceService
from app.schemas.app_api import (
    CallActionOut,
    CallActionIn,
    CallEndIn,
    CallEndOut,
    CallSessionActionsOut,
    CallStatusOut,
    CurrentCallSessionOut,
    DialingIn,
    DialingOut,
    RenewLeaseIn,
    RenewLeaseOut,
)
from app.schemas.base import Fail, Success
from tortoise.expressions import Q
from tortoise.transactions import in_transaction

router = APIRouter()

CALL_RING_TIMEOUT_SECONDS = 30
DEFAULT_FREE_SECONDS_BEFORE_BILLING = 10
DEFAULT_REJECT_INBOUND_PROTECT_SECONDS = 5
DEFAULT_REJECT_PAIR_PROTECT_SECONDS = 5
MAX_REJECT_PROTECT_SECONDS = 600
MAX_FREE_SECONDS_BEFORE_BILLING = 600

_call_trace_service = CallTraceService()


def _is_ring_timeout(call_record: CallRecord) -> bool:
    created_at = to_utc_aware(call_record.created_at)
    return datetime.now(timezone.utc) - created_at > timedelta(seconds=CALL_RING_TIMEOUT_SECONDS)


async def _mark_timeout_if_needed(call_record: CallRecord) -> bool:
    if call_record.status == "pending" and _is_ring_timeout(call_record):
        call_record.status = "ended"
        call_record.end_reason = "timeout"
        call_record.ended_at = now_local_naive()
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


def _calc_duration_seconds(call_record: CallRecord) -> int:
    if call_record.status != "ongoing" or not call_record.connected_at:
        return max(0, int(call_record.duration or 0))
    elapsed = (datetime.now(timezone.utc) - to_utc_aware(call_record.connected_at)).total_seconds()
    return max(0, int(elapsed))


def _to_iso(dt: datetime | None) -> str | None:
    if dt is None:
        return None
    return to_utc_aware(dt).isoformat()


async def _build_call_session_out(
    *,
    user_id: int,
    call_record: CallRecord | None,
) -> CurrentCallSessionOut:
    if call_record is None:
        return CurrentCallSessionOut()

    await _mark_timeout_if_needed(call_record)
    await call_record.refresh_from_db()

    caller_id = int(call_record.caller_id)
    callee_id = int(call_record.callee_id)
    is_caller = user_id == caller_id
    role = "caller" if is_caller else "callee"
    peer_user_id = callee_id if is_caller else caller_id
    peer = await AppUser.filter(id=peer_user_id).first()
    peer_nickname = (
        (peer.nickname or peer.username or f"用户{peer_user_id}")
        if peer
        else f"用户{peer_user_id}"
    )
    peer_avatar = peer.avatar if peer else None

    left_seconds = 0
    if call_record.status == "pending":
        created_at = to_utc_aware(call_record.created_at)
        elapsed = int((datetime.now(timezone.utc) - created_at).total_seconds())
        left_seconds = max(0, CALL_RING_TIMEOUT_SECONDS - elapsed)

    actions = CallSessionActionsOut(
        can_accept=(call_record.status == "pending" and role == "callee"),
        can_reject=(call_record.status == "pending" and role == "callee"),
        can_cancel=(call_record.status == "pending" and role == "caller"),
        can_hangup=(call_record.status == "ongoing"),
    )

    return CurrentCallSessionOut(
        call_id=call_record.id,
        status=call_record.status,
        role=role,
        end_reason=call_record.end_reason,
        peer_user_id=peer_user_id,
        peer_nickname=peer_nickname,
        peer_avatar=peer_avatar,
        call_price=int(call_record.call_price or 0),
        ring_timeout_seconds=CALL_RING_TIMEOUT_SECONDS,
        left_seconds=left_seconds,
        created_at=_to_iso(call_record.created_at),
        connected_at=_to_iso(call_record.connected_at),
        duration=_calc_duration_seconds(call_record),
        actions=actions,
    )


async def _get_free_seconds_before_billing() -> int:
    from app.models.system_config import SystemConfig

    raw = await SystemConfig.get_value(
        "call_billing_free_seconds",
        str(DEFAULT_FREE_SECONDS_BEFORE_BILLING),
    )
    seconds = _safe_parse_int(raw, DEFAULT_FREE_SECONDS_BEFORE_BILLING)
    if seconds < 0:
        return 0
    if seconds > MAX_FREE_SECONDS_BEFORE_BILLING:
        return MAX_FREE_SECONDS_BEFORE_BILLING
    return seconds


def _calc_due_minutes_with_free(duration_seconds: int, free_seconds_before_billing: int) -> int:
    if duration_seconds < free_seconds_before_billing:
        return 0
    return ((duration_seconds - free_seconds_before_billing) // 60) + 1


async def _resolve_payer_id(call_record: CallRecord) -> int:
    caller_id = int(call_record.caller_id)
    callee_id = int(call_record.callee_id)

    caller_is_anchor = await Anchor.filter(
        app_user_id=caller_id,
        apply_status="approved",
    ).exists()
    callee_is_anchor = await Anchor.filter(
        app_user_id=callee_id,
        apply_status="approved",
    ).exists()

    # 单主播场景：非主播承担通话费用
    if caller_is_anchor and not callee_is_anchor:
        return callee_id
    if callee_is_anchor and not caller_is_anchor:
        return caller_id

    # 兜底：双方角色无法区分时按主叫方计费
    return caller_id


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
        protect_since_inbound = now_local_naive() - timedelta(seconds=reject_inbound_protect_seconds)
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
            left = calc_left_seconds(
                latest_rejected_for_callee.updated_at,
                reject_inbound_protect_seconds,
            )
            if should_block_rejected_call(
                latest_rejected_for_callee.updated_at,
                reject_inbound_protect_seconds,
            ):
                return Fail(code=429, msg=f"对方暂不接听，请{left}秒后再试")

    if reject_pair_protect_seconds > 0:
        protect_since_pair = now_local_naive() - timedelta(seconds=reject_pair_protect_seconds)
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
            left = calc_left_seconds(
                latest_rejected_for_pair.updated_at,
                reject_pair_protect_seconds,
            )
            if should_block_rejected_call(
                latest_rejected_for_pair.updated_at,
                reject_pair_protect_seconds,
            ):
                return Fail(code=429, msg=f"你刚被对方拒绝，请{left}秒后再呼叫")

    call_price = anchor.call_price

    # 只做余额门槛检查，不预扣（视频通话消耗金币）
    if app_user.coins < call_price:
        return Fail(code=501, msg="余额不足，请先充值")

    # 创建通话记录（先 pending，待主播接听）
    call_record = await CallRecord.create(
        caller_id=caller_id,
        callee_id=anchor.app_user_id,
        call_price=call_price,
        status="pending",
    )
    callee_user = await AppUser.filter(id=anchor.app_user_id).first()
    callee_nickname = (
        (callee_user.nickname or callee_user.username or f"用户{anchor.app_user_id}")
        if callee_user
        else f"用户{anchor.app_user_id}"
    )
    callee_avatar = callee_user.avatar if callee_user else None
    await _append_call_trace(
        call_record,
        phase="dialing",
        actor_user_id=int(caller_id),
    )

    return Success(
        data=DialingOut(
            call_id=call_record.id,
            coins=app_user.coins,
            can_call=True,
            callee_id=int(anchor.app_user_id),
            callee_nickname=callee_nickname,
            callee_avatar=callee_avatar,
            call_price=int(call_price or 0),
            ring_timeout_seconds=CALL_RING_TIMEOUT_SECONDS,
            left_seconds=CALL_RING_TIMEOUT_SECONDS,
            msg="呼叫已发出，等待接听",
        ).model_dump()
    )


@router.get("/call/session/current", summary="查询当前通话会话", dependencies=[DependAppAuth])
async def current_call_session():
    user_id = CTX_APP_USER_ID.get()
    active_record = (
        await CallRecord.filter(
            (Q(caller_id=user_id) | Q(callee_id=user_id)),
            status__in=["pending", "ongoing"],
        )
        .order_by("-id")
        .first()
    )

    if active_record:
        session = await _build_call_session_out(user_id=user_id, call_record=active_record)
        return Success(data=session.model_dump())

    ended_record = (
        await CallRecord.filter(
            (Q(caller_id=user_id) | Q(callee_id=user_id)),
            status="ended",
        )
        .order_by("-id")
        .first()
    )
    session = await _build_call_session_out(user_id=user_id, call_record=ended_record)
    return Success(data=session.model_dump())


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
    duration = _calc_duration_seconds(call_record)

    return Success(
        data=CallStatusOut(
            call_id=call_record.id,
            caller_id=int(call_record.caller_id),
            callee_id=int(call_record.callee_id),
            status=call_record.status,
            created_at=to_utc_aware(call_record.created_at).isoformat() if call_record.created_at else None,
            end_reason=call_record.end_reason,
            duration=duration,
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
    call_record.connected_at = now_local_naive()
    call_record.duration = 0
    call_record.deducted_amount = 0
    call_record.deducted_minutes = 0
    call_record.last_renew_at = None
    call_record.ended_at = None
    await call_record.save()
    await _append_call_trace(
        call_record,
        phase="accepted",
        actor_user_id=int(user_id),
    )

    return Success(
        data=CallActionOut(next_status="ongoing", msg="已接听").model_dump(),
        msg="已接听",
    )


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
    call_record.ended_at = now_local_naive()
    await call_record.save()
    await _append_call_trace(
        call_record,
        phase="rejected",
        actor_user_id=int(user_id),
        reason="rejected",
    )

    return Success(
        data=CallActionOut(next_status="ended", msg="已拒绝").model_dump(),
        msg="已拒绝",
    )


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
    call_record.ended_at = now_local_naive()
    await call_record.save()
    await _append_call_trace(
        call_record,
        phase="cancelled",
        actor_user_id=int(user_id),
        reason="cancelled",
    )

    return Success(
        data=CallActionOut(next_status="ended", msg="已取消呼叫").model_dump(),
        msg="已取消呼叫",
    )


@router.post("/call/renew", summary="通话续租扣费", dependencies=[DependAppAuth])
async def renew_call(req_in: RenewLeaseIn):
    caller_id = CTX_APP_USER_ID.get()

    async with in_transaction() as conn:
        call_record = (
            await CallRecord.filter(id=req_in.call_id, status="ongoing")
            .using_db(conn)
            .select_for_update()
            .first()
        )
        if not call_record:
            return Fail(code=404, msg="通话不存在或已结束")

        if caller_id not in {int(call_record.caller_id), int(call_record.callee_id)}:
            return Fail(code=403, msg="无权续租该通话")

        duration_seconds = _calc_duration_seconds(call_record)
        free_seconds_before_billing = await _get_free_seconds_before_billing()
        due_minutes = _calc_due_minutes_with_free(
            duration_seconds,
            free_seconds_before_billing,
        )
        deducted_minutes = int(call_record.deducted_minutes or 0)
        to_charge_minutes = max(0, due_minutes - deducted_minutes)
        payer_id = await _resolve_payer_id(call_record)

        if to_charge_minutes > 0:
            charge_amount = to_charge_minutes * int(call_record.call_price or 0)
            updated = (
                await AppUser.filter(id=payer_id, coins__gte=charge_amount)
                .using_db(conn)
                .update(coins=AppUser.coins - charge_amount)
            )
            if updated == 0:
                call_record.status = "ended"
                call_record.end_reason = "balance_empty"
                call_record.duration = duration_seconds
                call_record.ended_at = now_local_naive()
                call_record.total_fee = int(call_record.deducted_amount or 0)
                await call_record.save(using_db=conn)
                await _append_call_trace(
                    call_record,
                    phase="balance_empty",
                    actor_user_id=int(payer_id),
                    reason="balance_empty",
                )
                return Fail(code=501, msg="余额不足，通话结束")

            call_record.deducted_minutes = deducted_minutes + to_charge_minutes
            call_record.deducted_amount = int(call_record.deducted_amount or 0) + charge_amount

        call_record.duration = duration_seconds
        call_record.last_renew_at = now_local_naive()
        await call_record.save(using_db=conn)

        user = await AppUser.filter(id=caller_id).using_db(conn).first()
        current_coins = user.coins if user else 0

    return Success(
        data=RenewLeaseOut(
            coins=current_coins,
            duration=duration_seconds,
            deducted_minutes=int(call_record.deducted_minutes or 0),
            deducted_amount=int(call_record.deducted_amount or 0),
            msg="OK",
        ).model_dump()
    )


@router.post("/call/end", summary="通话结束结算", dependencies=[DependAppAuth])
async def call_end(req_in: CallEndIn):
    user_id = CTX_APP_USER_ID.get()

    async with in_transaction() as conn:
        call_record = (
            await CallRecord.filter(id=req_in.call_id)
            .using_db(conn)
            .select_for_update()
            .first()
        )
        if not call_record:
            user = await AppUser.filter(id=user_id).using_db(conn).first()
            return Success(
                data=CallEndOut(
                    total_fee=0,
                    coins=user.coins if user else 0,
                    duration=0,
                    next_status="ended",
                    msg="通话已结束",
                ).model_dump()
            )

        if user_id not in {int(call_record.caller_id), int(call_record.callee_id)}:
            return Fail(code=403, msg="无权结束该通话")

        if call_record.status != "ended":
            duration_seconds = _calc_duration_seconds(call_record)
            call_record.duration = duration_seconds
            free_seconds_before_billing = await _get_free_seconds_before_billing()
            due_minutes = (
                _calc_due_minutes_with_free(duration_seconds, free_seconds_before_billing)
                if call_record.status == "ongoing"
                else 0
            )
            actual_fee = due_minutes * int(call_record.call_price or 0)
            deducted_amount = int(call_record.deducted_amount or 0)
            refund_amount = max(0, deducted_amount - actual_fee)
            charged_amount = deducted_amount - refund_amount
            payer_id = await _resolve_payer_id(call_record)

            if refund_amount > 0:
                await AppUser.filter(id=payer_id).using_db(conn).update(
                    coins=AppUser.coins + refund_amount
                )

            call_record.total_fee = charged_amount
            call_record.status = "ended"
            call_record.end_reason = call_record.end_reason or "normal"
            call_record.ended_at = now_local_naive()
            await call_record.save(using_db=conn)
            await _append_call_trace(
                call_record,
                phase="ended",
                actor_user_id=int(user_id),
                reason=call_record.end_reason,
            )

        user = await AppUser.filter(id=user_id).using_db(conn).first()
        final_coins = user.coins if user else 0

    return Success(
        data=CallEndOut(
            total_fee=int(call_record.total_fee or 0),
            coins=final_coins,
            duration=int(call_record.duration or 0),
            next_status="ended",
            msg="通话已结束",
        ).model_dump()
    )
