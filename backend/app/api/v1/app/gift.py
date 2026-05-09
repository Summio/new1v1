import asyncio

from fastapi import APIRouter, Depends
from tortoise.expressions import F
from tortoise.transactions import in_transaction

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID
from app.core.redis import get_redis
from app.models import AppUser, CallRecord, Gift, GiftRecord
from app.schemas.app_api import GiftSendIn, GiftSendOut
from app.schemas.base import Fail, Success, SuccessExtra
from app.services.gift_income_service import (
    calc_gift_certified_user_income_diamonds,
    decimal_to_float_2,
    get_gift_certified_user_share_bps,
)
from app.services.tim_service import send_gift_notification
from app.utils.media_url import to_relative_media_url

router = APIRouter()


async def _validate_call_scene(
    *,
    call_id: int | None,
    sender_id: int,
    target_user_id: int,
) -> bool:
    if call_id is None or call_id <= 0:
        return False
    call_record = await CallRecord.filter(
        id=call_id,
        status="ongoing",
    ).first()
    if not call_record:
        return False
    participants = {int(call_record.caller_id), int(call_record.callee_id)}
    return sender_id in participants and target_user_id in participants


@router.get("/gift/list", summary="礼物列表")
async def gift_list():
    try:
        redis = await get_redis()
        cached = await redis.get("gift:list:all")
        if cached:
            import json

            rows = json.loads(cached)
            return SuccessExtra(rows=rows, total=len(rows), has_more=False)
    except Exception:  # noqa: BLE001
        pass

    gifts = await Gift.filter(is_active=True).order_by("price")
    rows = [
        {
            "id": g.id,
            "name": g.name,
            "icon": to_relative_media_url(g.icon),
            "price": g.price,
            "svga_url": to_relative_media_url(g.svga_url),
        }
        for g in gifts
    ]

    try:
        import json

        redis = await get_redis()
        await redis.setex("gift:list:all", 300, json.dumps(rows))
    except Exception:  # noqa: BLE001
        pass

    return SuccessExtra(rows=rows, total=len(rows), has_more=False)


@router.post("/gift/send", summary="发送礼物", dependencies=[Depends(DependAppAuth)])
async def gift_send(req_in: GiftSendIn):
    sender_id = CTX_APP_USER_ID.get()

    gift = await Gift.filter(id=req_in.gift_id, is_active=True).first()
    if not gift:
        return Fail(code=404, msg="礼物不存在或已下架")

    target_user_id = int(req_in.target_user_id or 0)
    if target_user_id <= 0:
        return Fail(code=400, msg="目标用户参数错误")

    target_user = await AppUser.filter(
        id=target_user_id,
        status="normal",
    ).first()
    if not target_user:
        return Fail(code=404, msg="目标用户不存在或状态异常")

    scene = req_in.scene
    if scene == "call":
        is_valid_call = await _validate_call_scene(
            call_id=req_in.call_id,
            sender_id=int(sender_id),
            target_user_id=target_user_id,
        )
        if not is_valid_call:
            return Fail(code=400, msg="当前通话状态异常，无法送礼")
        from app.websocket.presence import is_online as check_target_online

        if not await check_target_online(target_user.id):
            return Fail(code=404, msg="对方不在线，暂无法发送礼物")

    quantity = int(req_in.quantity or 1)
    total_price = int(gift.price) * quantity
    if total_price <= 0:
        return Fail(code=400, msg="礼物金额异常")

    request_id = (req_in.request_id or "").strip()
    if request_id:
        idempotency_key = f"gift:send:req:{sender_id}:{request_id}"
        idempotency_ttl = 120
        try:
            redis = await get_redis()
            if not await redis.set(idempotency_key, "1", nx=True, ex=idempotency_ttl):
                return Fail(code=429, msg="请求过于频繁，请稍后再试")
        except Exception as e:  # noqa: BLE001
            from app.log import logger

            logger.warning("gift send idempotency check degraded: {}", str(e))

    sender = await AppUser.filter(id=sender_id).first()
    sender_nickname = sender.nickname if sender else f"用户{sender_id}"
    sender_avatar = to_relative_media_url(sender.avatar) if sender else None
    if not sender or decimal_to_float_2(sender.coins) < decimal_to_float_2(total_price):
        return Fail(code=501, msg="余额不足，请先充值")

    receiver_is_certified_user = bool(target_user.is_certified_user)
    certified_user_share_bps = await get_gift_certified_user_share_bps()
    certified_user_income_diamonds = (
        calc_gift_certified_user_income_diamonds(total_price, certified_user_share_bps)
        if receiver_is_certified_user
        else calc_gift_certified_user_income_diamonds(0, certified_user_share_bps)
    )
    current_coins = 0.0
    try:
        async with in_transaction() as conn:
            updated = (
                await AppUser.filter(
                    id=sender_id,
                    coins__gte=total_price,
                )
                .using_db(conn)
                .update(coins=F("coins") - total_price)
            )
            if updated == 0:
                raise ValueError("余额不足，扣款失败")

            if certified_user_income_diamonds > 0:
                await AppUser.filter(id=target_user.id).using_db(conn).update(
                    diamonds=F("diamonds") + certified_user_income_diamonds,
                )

            await GiftRecord.create(
                sender_id=sender_id,
                receiver_id=target_user.id,
                gift_id=gift.id,
                gift_name=gift.name,
                price=gift.price,
                quantity=quantity,
                total_price=total_price,
                certified_user_share_bps=certified_user_share_bps,
                certified_user_income_diamonds=certified_user_income_diamonds,
                using_db=conn,
            )

            sender_after = await AppUser.filter(id=sender_id).using_db(conn).first()
            current_coins = decimal_to_float_2(sender_after.coins) if sender_after else 0.0
    except ValueError:
        return Fail(code=501, msg="余额不足，请先充值")

    icon = to_relative_media_url(gift.icon)
    svga_url = to_relative_media_url(gift.svga_url)
    call_id = req_in.call_id if scene == "call" else None
    asyncio.create_task(
        send_gift_notification(
            sender_id=sender_id,
            receiver_id=target_user.id,
            gift_id=int(gift.id),
            gift_name=gift.name,
            gift_icon=icon,
            svga_url=svga_url,
            gift_price=int(gift.price),
            quantity=quantity,
            total_price=total_price,
            certified_user_income_diamonds=decimal_to_float_2(certified_user_income_diamonds),
            scene=scene,
            call_id=call_id,
            sender_nickname=sender_nickname,
        )
    )

    asyncio.create_task(
        _ws_push_gift_sent(
            sender_id=int(sender_id),
            gift_id=int(gift.id),
            gift_name=gift.name,
            gift_icon=icon,
            svga_url=svga_url,
            gift_price=int(gift.price),
            quantity=quantity,
            total_price=total_price,
            certified_user_income_diamonds=decimal_to_float_2(certified_user_income_diamonds),
            scene=scene,
            call_id=call_id,
            sender_nickname=sender_nickname,
            receiver_coins=current_coins,
        )
    )
    asyncio.create_task(
        _ws_push_gift_received(
            target_user_id=int(target_user.id),
            sender_id=int(sender_id),
            sender_nickname=sender_nickname,
            sender_avatar=sender_avatar,
            gift_id=int(gift.id),
            gift_name=gift.name,
            gift_icon=icon,
            svga_url=svga_url,
            gift_price=int(gift.price),
            quantity=quantity,
            total_price=total_price,
            certified_user_income_diamonds=decimal_to_float_2(certified_user_income_diamonds),
            scene=scene,
            call_id=call_id,
        )
    )

    return Success(
        data=GiftSendOut(
            gift_id=int(gift.id),
            gift_name=gift.name,
            gift_icon=icon,
            svga_url=svga_url,
            quantity=quantity,
            unit_price=int(gift.price),
            total_price=total_price,
            certified_user_income_diamonds=decimal_to_float_2(certified_user_income_diamonds),
            coins=current_coins,
            msg="发送成功",
        ).model_dump()
    )


async def _ws_push_gift_sent(
    *,
    sender_id: int,
    gift_id: int,
    gift_name: str,
    gift_icon: str,
    svga_url: str | None,
    gift_price: int,
    quantity: int,
    total_price: int,
    certified_user_income_diamonds: float,
    scene: str,
    call_id: int | None,
    sender_nickname: str,
    receiver_coins: float,
) -> None:
    try:
        from app.websocket import events as ws_events

        await ws_events.push_gift_sent(
            sender_id=sender_id,
            gift_id=gift_id,
            gift_name=gift_name,
            gift_icon=gift_icon,
            svga_url=svga_url,
            gift_price=gift_price,
            quantity=quantity,
            total_price=total_price,
            certified_user_income_diamonds=certified_user_income_diamonds,
            scene=scene,
            call_id=call_id,
            sender_nickname=sender_nickname,
            receiver_coins=receiver_coins,
        )
    except Exception:  # noqa: BLE001
        pass


async def _ws_push_gift_received(
    *,
    target_user_id: int,
    sender_id: int,
    sender_nickname: str,
    sender_avatar: str | None,
    gift_id: int,
    gift_name: str,
    gift_icon: str,
    svga_url: str | None,
    gift_price: int,
    quantity: int,
    total_price: int,
    certified_user_income_diamonds: float,
    scene: str,
    call_id: int | None,
) -> None:
    try:
        from app.websocket import events as ws_events

        await ws_events.push_gift_received(
            target_user_id=target_user_id,
            sender_id=sender_id,
            sender_nickname=sender_nickname,
            sender_avatar=sender_avatar,
            gift_id=gift_id,
            gift_name=gift_name,
            gift_icon=gift_icon,
            svga_url=svga_url,
            gift_price=gift_price,
            quantity=quantity,
            total_price=total_price,
            certified_user_income_diamonds=certified_user_income_diamonds,
            scene=scene,
            call_id=call_id,
        )
    except Exception:  # noqa: BLE001
        pass

