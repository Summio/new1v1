"""Tencent IM 统一发送服务。

提供 C2C 自定义消息发送能力，被 CallTraceService 和礼物信令模块共用。
"""
from __future__ import annotations

import asyncio
import json
import random
import time
from urllib.parse import urlencode

from loguru import logger

# ===== 协议标识 =====
GIFT_NOTIFY_PROTOCOL = "gift_notify.v1"

# ===== 缓存 TTL =====
_USERSIG_BUFFER_SECONDS = 30
_USERSIG_EXPIRE_SECONDS = 600  # 腾讯 IM 默认最大有效期

# ===== 重试参数 =====
_MAX_RETRIES = 3
_RETRY_BASE_DELAY = 1.0  # 秒

# ===== 共享 IM 配置缓存（供 TIMService 和 CallTraceService 共用，避免重复查询 DB）=====
_IM_CONFIG_SHARED_TTL_SECONDS = 60
_im_config_shared_cache: dict[str, str] | None = None
_im_config_shared_expire_at: float = 0


async def get_shared_im_config() -> dict[str, str]:
    """获取 IM 系统配置，带模块级内存缓存，TTL 60s。

    S-3 修复：TIMService 和 CallTraceService 共用此函数，
    避免各自独立缓存导致 DB 查询重复。
    """
    global _im_config_shared_cache, _im_config_shared_expire_at
    now = time.time()
    if _im_config_shared_cache is not None and now < _im_config_shared_expire_at:
        return _im_config_shared_cache

    from app.models.system_config import SystemConfig

    _im_config_shared_cache = await SystemConfig.get_all_as_dict()
    _im_config_shared_expire_at = now + _IM_CONFIG_SHARED_TTL_SECONDS
    return _im_config_shared_cache


class TIMService:
    """Tencent IM 发送服务（带配置缓存和 UserSig 缓存）。"""

    _instance: "TIMService | None" = None

    def __init__(self) -> None:
        # IM 配置改用 get_shared_im_config() 共享缓存
        self._usersig_cache: tuple[str, int] | None = None  # (sig, expire_ts)

    @classmethod
    def get_instance(cls) -> "TIMService":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    async def _get_im_config(self) -> dict[str, str]:
        return await get_shared_im_config()

    async def _get_admin_usersig(self, sdk_app_id: int, secret_key: str, identifier: str) -> str:
        now = time.time()
        if (
            self._usersig_cache is not None
            and self._usersig_cache[1] - _USERSIG_BUFFER_SECONDS > now
        ):
            return self._usersig_cache[0]

        from TLSSigAPIv2 import TLSSigAPIv2

        api = TLSSigAPIv2(sdk_app_id, secret_key)
        sig = api.gen_sig(identifier=identifier, expire=_USERSIG_EXPIRE_SECONDS)
        expire_ts = int(now) + _USERSIG_EXPIRE_SECONDS
        self._usersig_cache = (sig, expire_ts)
        return sig

    @staticmethod
    def _to_im_account(user_id: int) -> str:
        return f"chat_{user_id}"

    async def _send_c2c_custom_msg(
        self,
        *,
        sdk_app_id: int,
        identifier: str,
        usersig: str,
        from_account: str,
        to_account: str,
        event: dict,
        desc: str = "custom_msg",
    ) -> bool:
        try:
            import httpx
        except Exception as exc:  # noqa: BLE001
            logger.warning("tim send skipped: httpx unavailable, err={}", str(exc))
            return False

        query = urlencode(
            {
                "sdkappid": sdk_app_id,
                "identifier": identifier,
                "usersig": usersig,
                "random": random.randint(100000, 999999),
                "contenttype": "json",
            }
        )
        url = f"https://console.tim.qq.com/v4/openim/sendmsg?{query}"
        payload = {
            "SyncOtherMachine": 1,
            "From_Account": from_account,
            "To_Account": to_account,
            "MsgRandom": random.randint(100000, 999999),
            "MsgBody": [
                {
                    "MsgType": "TIMCustomElem",
                    "MsgContent": {
                        "Data": json.dumps(event, ensure_ascii=False, separators=(",", ":")),
                        "Desc": desc,
                    },
                }
            ],
        }

        for attempt in range(_MAX_RETRIES):
            try:
                async with httpx.AsyncClient(timeout=8.0) as client:
                    resp = await client.post(url, json=payload)
            except Exception as exc:  # noqa: BLE001
                logger.warning("tim send failed (attempt {}/{}): {}", attempt + 1, _MAX_RETRIES, str(exc))
                if attempt < _MAX_RETRIES - 1:
                    await asyncio.sleep(_RETRY_BASE_DELAY * (2 ** attempt))
                    continue
                return False

            if resp.status_code != 200:
                logger.warning("tim send failed (attempt {}/{}): http_status={}", attempt + 1, _MAX_RETRIES, resp.status_code)
                if attempt < _MAX_RETRIES - 1:
                    await asyncio.sleep(_RETRY_BASE_DELAY * (2 ** attempt))
                    continue
                return False

            try:
                body = resp.json()
            except ValueError:
                if attempt < _MAX_RETRIES - 1:
                    await asyncio.sleep(_RETRY_BASE_DELAY * (2 ** attempt))
                    continue
                return False

            if int(body.get("ErrorCode", -1)) != 0:
                logger.warning("tim send failed (attempt {}/{}): body={}", attempt + 1, _MAX_RETRIES, body)
                if attempt < _MAX_RETRIES - 1:
                    await asyncio.sleep(_RETRY_BASE_DELAY * (2 ** attempt))
                    continue
                return False

            return True

        return False

    async def send_gift_notification(
        self,
        *,
        sender_id: int,
        receiver_id: int,
        gift_id: int,
        gift_name: str,
        gift_icon: str,
        svga_url: str | None,
        gift_price: int,
        quantity: int,
        total_price: int,
        anchor_income_diamonds: str,
        scene: str,
        call_id: int | None,
        sender_nickname: str,
    ) -> bool:
        """发送礼物通知 IM 信令给收礼方（认证用户）。

        信令内容：
          {
            "type": "gift_notify",
            "gift_name": "...,
            "gift_icon": "...",
            "gift_price": 10,
            "sender_id": 123,
            "sender_nickname": "...",
            "ts": 1234567890
          }
        """
        try:
            config = await self._get_im_config()
            sdk_app_id_raw = (config.get("im_sdk_app_id") or "").strip()
            secret_key = (config.get("im_secret_key") or "").strip()

            if not sdk_app_id_raw or not secret_key:
                logger.warning("gift im notify skipped: IM not configured")
                return False

            sdk_app_id = int(sdk_app_id_raw)
        except Exception as exc:  # noqa: BLE001
            logger.warning("gift im notify skipped: config error, err={}", str(exc))
            return False

        admin_identifier = (config.get("im_admin_identifier") or "admin").strip()

        try:
            usersig = await self._get_admin_usersig(sdk_app_id, secret_key, admin_identifier)
        except Exception as exc:  # noqa: BLE001
            logger.warning("gift im notify skipped: usersig error, err={}", str(exc))
            return False

        event = {
            "type": "gift_notify",
            "gift_id": gift_id,
            "gift_name": gift_name,
            "gift_icon": gift_icon,
            "svga_url": svga_url,
            "gift_price": gift_price,
            "unit_price": gift_price,
            "quantity": quantity,
            "total_price": total_price,
            "anchor_income_diamonds": anchor_income_diamonds,
            "scene": scene,
            "call_id": call_id,
            "sender_id": sender_id,
            "sender_nickname": sender_nickname,
            "ts": int(time.time()),
        }

        return await self._send_c2c_custom_msg(
            sdk_app_id=sdk_app_id,
            identifier=admin_identifier,
            usersig=usersig,
            from_account=self._to_im_account(sender_id),
            to_account=self._to_im_account(receiver_id),
            event=event,
            desc=GIFT_NOTIFY_PROTOCOL,
        )


# ===== 便捷单例函数 =====
_tim_service: TIMService | None = None


def get_tim_service() -> TIMService:
    global _tim_service
    if _tim_service is None:
        _tim_service = TIMService()
    return _tim_service


async def send_gift_notification(
    sender_id: int,
    receiver_id: int,
    gift_id: int,
    gift_name: str,
    gift_icon: str,
    svga_url: str | None,
    gift_price: int,
    quantity: int,
    total_price: int,
    anchor_income_diamonds: str,
    scene: str,
    call_id: int | None,
    sender_nickname: str,
) -> bool:
    """发送礼物通知 IM 信令。"""
    return await get_tim_service().send_gift_notification(
        sender_id=sender_id,
        receiver_id=receiver_id,
        gift_id=gift_id,
        gift_name=gift_name,
        gift_icon=gift_icon,
        svga_url=svga_url,
        gift_price=gift_price,
        quantity=quantity,
        total_price=total_price,
        anchor_income_diamonds=anchor_income_diamonds,
        scene=scene,
        call_id=call_id,
        sender_nickname=sender_nickname,
    )
