"""WebSocket 事件推送工具。

业务代码调用这些函数，内部通过 ConnectionManager.push_to_user
走 Redis Pub/Sub 广播到所有 worker，目标 worker 负责转发 WebSocket 帧。

所有函数均为 async，通过 asyncio.create_task 异步调用，不阻塞主流程。
"""

from __future__ import annotations

import asyncio
from typing import Any

from app.websocket.manager import get_manager

# ===== 类型别名 =====

PushResult = bool


# ===== 通话事件 =====

async def push_call_incoming(
    callee_id: int,
    call_id: int,
    caller_id: int,
    caller_name: str,
    caller_avatar: str | None,
    call_price: int,
    left_seconds: int,
) -> PushResult:
    """推送来电给被叫方。"""
    data = {
        "call_id": call_id,
        "caller_id": int(caller_id),
        "caller_name": caller_name,
        "caller_avatar": caller_avatar,
        "call_price": int(call_price),
        "left_seconds": int(left_seconds),
    }
    return await get_manager().push_to_user(int(callee_id), "call_incoming", data)


async def push_call_accepted(
    caller_id: int,
    call_id: int,
) -> PushResult:
    """推送通话已接听给主叫方。"""
    data = {"call_id": int(call_id)}
    return await get_manager().push_to_user(int(caller_id), "call_accepted", data)


async def push_call_rejected(
    caller_id: int,
    call_id: int,
    reason: str | None = None,
) -> PushResult:
    """推送通话被拒绝给主叫方。"""
    data = {"call_id": int(call_id), "reason": reason}
    return await get_manager().push_to_user(int(caller_id), "call_rejected", data)


async def push_call_cancelled(
    callee_id: int,
    call_id: int,
    reason: str | None = None,
) -> PushResult:
    """推送主叫取消给被叫方。"""
    data = {"call_id": int(call_id), "reason": reason}
    return await get_manager().push_to_user(int(callee_id), "call_cancelled", data)


async def push_call_ended(
    caller_id: int,
    callee_id: int,
    call_id: int,
    end_reason: str | None = None,
) -> PushResult:
    """推送通话结束给双方。"""
    data = {"call_id": int(call_id), "end_reason": end_reason}
    tasks = [
        get_manager().push_to_user(int(caller_id), "call_ended", data, critical=True),
        get_manager().push_to_user(int(callee_id), "call_ended", data, critical=True),
    ]
    results = await asyncio.gather(*tasks)
    return all(results)


async def push_call_timeout(
    caller_id: int,
    callee_id: int,
    call_id: int,
) -> PushResult:
    """推送通话超时给双方（watchdog 关闭 pending 通话）。"""
    data = {"call_id": int(call_id)}
    tasks = [
        get_manager().push_to_user(int(caller_id), "call_timeout", data, critical=True),
        get_manager().push_to_user(int(callee_id), "call_timeout", data, critical=True),
    ]
    results = await asyncio.gather(*tasks)
    return all(results)


async def push_call_balance_empty(
    caller_id: int,
    callee_id: int,
    call_id: int,
) -> PushResult:
    """推送余额不足通话结束给双方（watchdog 关闭 ongoing 通话）。"""
    data = {"call_id": int(call_id)}
    tasks = [
        get_manager().push_to_user(int(caller_id), "call_balance_empty", data, critical=True),
        get_manager().push_to_user(int(callee_id), "call_balance_empty", data, critical=True),
    ]
    results = await asyncio.gather(*tasks)
    return all(results)


# ===== 礼物事件 =====

async def push_gift_sent(
    sender_id: int,
    gift_name: str,
    gift_icon: str,
    gift_price: int,
    quantity: int,
    sender_nickname: str,
    receiver_coins: int,
) -> PushResult:
    """推送礼物发送确认给发送方。"""
    data = {
        "gift_name": gift_name,
        "gift_icon": gift_icon,
        "gift_price": int(gift_price),
        "quantity": int(quantity),
        "sender_nickname": sender_nickname,
        "receiver_coins": int(receiver_coins),
    }
    return await get_manager().push_to_user(int(sender_id), "gift_sent", data)


async def push_gift_received(
    anchor_id: int,
    sender_id: int,
    sender_nickname: str,
    sender_avatar: str | None,
    gift_id: int,
    gift_name: str,
    gift_icon: str,
    gift_price: int,
) -> PushResult:
    """推送收到礼物给主播，用于展示礼物动画。"""
    data = {
        "gift_id": int(gift_id),
        "gift_name": gift_name,
        "gift_icon": gift_icon,
        "gift_price": int(gift_price),
        "sender_id": int(sender_id),
        "sender_nickname": sender_nickname,
        "sender_avatar": sender_avatar,
    }
    return await get_manager().push_to_user(int(anchor_id), "gift_received", data)


# ===== 余额事件 =====

async def push_balance_update(
    user_id: int,
    coins: int,
    diamonds: int,
) -> PushResult:
    """推送余额变更给用户（充值成功后调用）。"""
    data = {
        "coins": int(coins),
        "diamonds": int(diamonds),
    }
    return await get_manager().push_to_user(int(user_id), "balance_updated", data, critical=True)


# ===== 在线状态事件 =====

async def push_presence(
    user_id: int,
    online: bool,
) -> PushResult:
    """推送用户在线/离线状态变更。"""
    data = {
        "user_id": int(user_id),
        "online": bool(online),
    }
    return await get_manager().push_to_user(int(user_id), "presence", data, critical=True)
