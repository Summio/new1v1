import asyncio
from fastapi import APIRouter, Depends
from tortoise.expressions import F
from tortoise.transactions import in_transaction

from app.core.app_auth import DependAppAuth
from app.core.ctx import CTX_APP_USER_ID
from app.core.redis import get_redis
from app.models import AppUser, Gift, GiftRecord
from app.schemas.app_api import GiftSendIn, GiftSendOut
from app.schemas.base import Fail, Success, SuccessExtra
from app.services.tim_service import send_gift_notification
from app.utils.media_url import to_relative_media_url

router = APIRouter()

# ===== 礼物列表（Redis 缓存，TTL 300s） =====


@router.get("/gift/list", summary="礼物列表")
async def gift_list():
    try:
        redis = await get_redis()
        cached = await redis.get("gift:list:all")
        if cached:
            import json

            return SuccessExtra(
                rows=json.loads(cached),
                total=len(json.loads(cached)),
                has_more=False,
            )
    except Exception:  # noqa: BLE001
        pass  # Redis 不可用时回退到数据库查询

    gifts = await Gift.filter(is_active=True).order_by("price")
    rows = [
        {
            "id": g.id,
            "name": g.name,
            "icon": g.icon,
            "price": g.price,
        }
        for g in gifts
    ]

    # 缓存结果（礼物列表变更频率低）
    try:
        import json

        redis = await get_redis()
        await redis.setex("gift:list:all", 300, json.dumps(rows))
    except Exception:  # noqa: BLE001
        pass

    return SuccessExtra(rows=rows, total=len(rows), has_more=False)

# ===== 发送礼物 =====


@router.post("/gift/send", summary="发送礼物", dependencies=[Depends(DependAppAuth)])
async def gift_send(req_in: GiftSendIn):
    sender_id = CTX_APP_USER_ID.get()

    # 查找礼物
    gift = await Gift.filter(id=req_in.gift_id, is_active=True).first()
    if not gift:
        return Fail(code=404, msg="礼物不存在或已下架")

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

    # P17 + L-5 修复：使用 Redis 在线状态检查（WebSocket 方式）
    from app.websocket.presence import is_online as check_anchor_online
    if not await check_anchor_online(anchor_user.id):
        return Fail(code=404, msg="主播不在线，暂无法发送礼物")

    # C-3 修复：原子 SET NX EX，TTL 从 30s 增至 60s，避免 setnx+expire 非原子导致的竞态窗口
    idempotency_key = f"gift:send:{sender_id}:{req_in.gift_id}:{anchor_user_id}"
    try:
        redis = await get_redis()
        if not await redis.set(idempotency_key, "1", nx=True, ex=60):
            return Fail(code=429, msg="请求过于频繁，请稍后再试")
    except Exception as e:  # noqa: BLE001
        # H1 修复：Redis 不可用时跳过幂等检查，但记录日志供监控
        from app.log import logger
        logger.warning("gift send idempotency check degraded: {}", str(e))

    # L-2 修复：先查昵称（只读查询，无锁），再开启事务扣钻
    sender = await AppUser.filter(id=sender_id).first()
    sender_nickname = sender.nickname if sender else f"用户{sender_id}"
    sender_avatar = to_relative_media_url(sender.avatar) if sender else None

    # H3 修复：余额检查放在事务外，避免在 async with in_transaction() 块内 return
    if not sender or sender.coins < gift.price:
        return Fail(code=501, msg="余额不足，请先充值")

    current_coins = 0
    try:
        async with in_transaction() as conn:
            # 原子扣费：使用条件更新避免竞态（扣金币）
            updated = await AppUser.filter(id=sender_id, coins__gte=gift.price).using_db(conn).update(
                coins=F("coins") - gift.price
            )
            if updated == 0:
                raise ValueError("余额不足，扣款失败")

            # 记录礼物（同一事务内）
            await GiftRecord.create(
                sender_id=sender_id,
                receiver_id=anchor_user.id,
                gift_id=gift.id,
                gift_name=gift.name,
                price=gift.price,
                using_db=conn,
            )

            # 获取扣钻后的最新余额
            sender_after = await AppUser.filter(id=sender_id).using_db(conn).first()
            current_coins = sender_after.coins if sender_after else 0
    except ValueError:
        return Fail(code=501, msg="余额不足，请先充值")

    # BL-4: 事务已提交，异步下发 IM 礼物通知信令（不阻塞响应）
    asyncio.create_task(
        send_gift_notification(
            sender_id=sender_id,
            receiver_id=anchor_user.id,
            gift_name=gift.name,
            gift_icon=gift.icon or "",
            gift_price=gift.price,
            sender_nickname=sender_nickname,
        )
    )

    # 推送 WebSocket 礼物通知给主播（fire-and-forget）
    asyncio.create_task(_ws_push_gift_received(
        anchor_id=int(anchor_user.id),
        sender_id=sender_id,
        sender_nickname=sender_nickname,
        sender_avatar=sender_avatar,
        gift_id=gift.id,
        gift_name=gift.name,
        gift_icon=gift.icon or "",
        gift_price=gift.price,
    ))

    return Success(
        data=GiftSendOut(
            gift_name=gift.name,
            coins=current_coins,
            msg="发送成功",
        ).model_dump()
    )


# ===== WebSocket 推送辅助函数（fire-and-forget） =====

async def _ws_push_gift_received(
    anchor_id: int,
    sender_id: int,
    sender_nickname: str,
    sender_avatar: str | None,
    gift_id: int,
    gift_name: str,
    gift_icon: str,
    gift_price: int,
) -> None:
    try:
        from app.websocket import events as ws_events
        await ws_events.push_gift_received(
            anchor_id=anchor_id,
            sender_id=sender_id,
            sender_nickname=sender_nickname,
            sender_avatar=sender_avatar,
            gift_id=gift_id,
            gift_name=gift_name,
            gift_icon=gift_icon,
            gift_price=gift_price,
        )
    except Exception:  # noqa: BLE001
        pass
