from __future__ import annotations

import asyncio
import json
import random
from datetime import datetime, timezone
from typing import Any, Awaitable, Callable
from urllib.parse import urlencode

from loguru import logger

CALL_TRACE_PROTOCOL = "call_trace.v1"
VALID_CALL_TRACE_PHASES = {
    "dialing",
    "accepted",
    "rejected",
    "cancelled",
    "ended",
    "timeout",
    "balance_empty",
}

DEFAULT_CALL_TRACE_DEDUPE_TTL_SECONDS = 7 * 24 * 60 * 60
DEFAULT_IM_ADMIN_IDENTIFIER = "trace_bot"

# 缓存 TTL
_USERSIG_CACHE_BUFFER_SECONDS = 30  # 提前 30 秒刷新

EnabledGetter = Callable[[], Awaitable[bool]]
IdempotencyClaimer = Callable[[str], Awaitable[bool]]
MessageSender = Callable[..., Awaitable[bool]]


def make_call_trace_dedupe_key(call_id: int, phase: str) -> str:
    return f"call:trace:{int(call_id)}:{phase}"


def _safe_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _now_ts_seconds() -> int:
    return int(datetime.now(timezone.utc).timestamp())


def _to_im_account(user_id: int) -> str:
    return f"chat_{int(user_id)}"


def _parse_bool(raw: str | None, default: bool = False) -> bool:
    if raw is None:
        return default
    normalized = str(raw).strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False
    return default


def build_call_trace_event(
    *,
    call_record: Any,
    phase: str,
    actor_user_id: int,
    reason: str | None = None,
    ts: int | None = None,
) -> dict[str, Any]:
    if phase not in VALID_CALL_TRACE_PHASES:
        raise ValueError(f"Unsupported call trace phase: {phase}")

    call_id = _safe_int(getattr(call_record, "id", 0))
    caller_id = _safe_int(getattr(call_record, "caller_id", 0))
    callee_id = _safe_int(getattr(call_record, "callee_id", 0))
    actor_id = _safe_int(actor_user_id, caller_id)
    if actor_id == callee_id:
        peer_id = caller_id
    else:
        peer_id = callee_id

    return {
        "protocol": CALL_TRACE_PROTOCOL,
        "event_id": make_call_trace_dedupe_key(call_id=call_id, phase=phase),
        "call_id": call_id,
        "phase": phase,
        "actor_user_id": actor_id,
        "peer_user_id": peer_id,
        "ts": ts or _now_ts_seconds(),
        "duration_seconds": _safe_int(getattr(call_record, "duration", 0)),
        "total_fee_coins": _safe_int(getattr(call_record, "total_fee", 0)),
        "reason": reason,
    }


# Lua 脚本：原子化地去重 + 发送。
# KEYS[1] = dedupe_key
# ARGV[1] = dedupe_ttl
# 返回 "claimed" 表示去重 key 被占用（跳过），返回 "send" 表示需要发送
_DEDUPE_AND_SEND_LUA = """
local exists = redis.call('EXISTS', KEYS[1])
if exists == 1 then
    return 'skipped'
end
redis.call('SETEX', KEYS[1], ARGV[1], '1')
return 'send'
"""


class CallTraceService:
    def __init__(
        self,
        *,
        enabled_getter: EnabledGetter | None = None,
        idempotency_claimer: IdempotencyClaimer | None = None,
        message_sender: MessageSender | None = None,
        dedupe_ttl_seconds: int = DEFAULT_CALL_TRACE_DEDUPE_TTL_SECONDS,
    ) -> None:
        self._enabled_getter = enabled_getter or self._default_enabled_getter
        self._idempotency_claimer = idempotency_claimer or self._default_idempotency_claimer
        self._message_sender = message_sender or self._default_message_sender
        self._dedupe_ttl_seconds = max(60, int(dedupe_ttl_seconds))

        # 缓存：UserSig（IM 配置改用 get_shared_im_config 共享缓存）
        self._usersig_cache: tuple[str, int] | None = None  # (sig, expire_ts)
        self._usersig_sha: str | None = None
        self._lua_sha: str | None = None

    async def append(
        self,
        call_record: Any,
        *,
        phase: str,
        actor_user_id: int | None = None,
        reason: str | None = None,
        ts: int | None = None,
    ) -> bool:
        if phase not in VALID_CALL_TRACE_PHASES:
            logger.warning("call trace skipped: invalid phase {}", phase)
            return False

        try:
            enabled = await self._enabled_getter()
            if not enabled:
                return False

            call_id = _safe_int(getattr(call_record, "id", 0))
            dedupe_key = make_call_trace_dedupe_key(call_id=call_id, phase=phase)
            claimed = await self._idempotency_claimer(dedupe_key)
            if not claimed:
                return False

            actor_id = _safe_int(
                actor_user_id,
                _safe_int(getattr(call_record, "caller_id", 0)),
            )
            event = build_call_trace_event(
                call_record=call_record,
                phase=phase,
                actor_user_id=actor_id,
                reason=reason,
                ts=ts,
            )
            return await self._message_sender(
                from_user_id=event["actor_user_id"],
                to_user_id=event["peer_user_id"],
                event=event,
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning("call trace append failed: {}", str(exc))
            return False

    async def _default_enabled_getter(self) -> bool:
        config = await self._get_im_config()
        raw = config.get("im_call_trace_enabled", "1")
        return _parse_bool(raw, default=True)

    async def _get_im_config(self) -> dict[str, Any]:
        from app.services.tim_service import get_shared_im_config
        return await get_shared_im_config()

    async def _get_cached_usersig(self, identifier: str, sdk_app_id: int, secret_key: str) -> str:
        """获取 UserSig，带缓存，过期前 _USERSIG_CACHE_BUFFER_SECONDS 秒刷新。"""
        now = _now_ts_seconds()
        if (
            self._usersig_cache is not None
            and self._usersig_cache[1] - _USERSIG_CACHE_BUFFER_SECONDS > now
        ):
            return self._usersig_cache[0]

        from TLSSigAPIv2 import TLSSigAPIv2

        api = TLSSigAPIv2(sdk_app_id, secret_key)
        # 签名有效期 600 秒（腾讯 IM 默认最大）
        sig = api.gen_sig(identifier=identifier, expire=600)
        expire_ts = now + 600
        self._usersig_cache = (sig, expire_ts)
        return sig

    async def _default_idempotency_claimer(self, key: str) -> bool:
        from app.core.redis import get_redis

        redis_client = await get_redis()
        # 尝试获取 Lua 脚本 SHA（已缓存）
        if self._lua_sha is None:
            self._lua_sha = await redis_client.script_load(_DEDUPE_AND_SEND_LUA)
        try:
            result = await redis_client.evalsha(
                self._lua_sha, 1, key, self._dedupe_ttl_seconds
            )
            return result == "send"
        except redis.exceptions.ResponseError as e:
            # W-7 修复：NOSCRIPT 说明脚本被 Redis 清除，重新加载后重试
            if "NOSCRIPT" in str(e):
                self._lua_sha = await redis_client.script_load(_DEDUPE_AND_SEND_LUA)
                result = await redis_client.evalsha(
                    self._lua_sha, 1, key, self._dedupe_ttl_seconds
                )
                return result == "send"
            # 其他错误回退到 SETNX
            claimed = await redis_client.set(
                key,
                "1",
                ex=self._dedupe_ttl_seconds,
                nx=True,
            )
            return bool(claimed)
        except Exception:  # noqa: BLE001
            # 回退：普通 SETNX
            claimed = await redis_client.set(
                key,
                "1",
                ex=self._dedupe_ttl_seconds,
                nx=True,
            )
            return bool(claimed)

    async def _default_message_sender(
        self,
        *,
        from_user_id: int,
        to_user_id: int,
        event: dict[str, Any],
    ) -> bool:
        config = await self._get_im_config()
        sdk_app_id_raw = (config.get("im_sdk_app_id") or "").strip()
        secret_key = (config.get("im_secret_key") or "").strip()
        admin_identifier = (config.get("im_admin_identifier") or DEFAULT_IM_ADMIN_IDENTIFIER).strip()

        if not sdk_app_id_raw or not secret_key:
            logger.warning("call trace skipped: im config missing")
            return False

        try:
            sdk_app_id = int(sdk_app_id_raw)
        except ValueError:
            logger.warning("call trace skipped: invalid im_sdk_app_id {}", sdk_app_id_raw)
            return False

        try:
            admin_usersig = await self._get_cached_usersig(
                identifier=admin_identifier,
                sdk_app_id=sdk_app_id,
                secret_key=secret_key,
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning("call trace skipped: TLSSigAPIv2 unavailable, err={}", str(exc))
            return False

        return await self._send_tim_custom_message(
            sdk_app_id=sdk_app_id,
            identifier=admin_identifier,
            usersig=admin_usersig,
            from_account=_to_im_account(from_user_id),
            to_account=_to_im_account(to_user_id),
            event=event,
        )

    async def _send_tim_custom_message(
        self,
        *,
        sdk_app_id: int,
        identifier: str,
        usersig: str,
        from_account: str,
        to_account: str,
        event: dict[str, Any],
    ) -> bool:
        try:
            import httpx
        except Exception as exc:  # noqa: BLE001
            logger.warning("call trace skipped: httpx unavailable, err={}", str(exc))
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
                        "Desc": CALL_TRACE_PROTOCOL,
                        "Ext": "call_trace",
                    },
                }
            ],
        }

        # 重试：最多 3 次，指数退避 1s / 2s / 4s
        max_retries = 3
        for attempt in range(max_retries):
            try:
                async with httpx.AsyncClient(timeout=8.0) as client:
                    resp = await client.post(url, json=payload)
            except Exception as exc:  # noqa: BLE001
                logger.warning("call trace send failed (attempt {}/{}): {}", attempt + 1, max_retries, str(exc))
                if attempt < max_retries - 1:
                    await asyncio.sleep(2 ** attempt)
                    continue
                return False

            if resp.status_code != 200:
                logger.warning("call trace send failed (attempt {}/{}): http_status={}", attempt + 1, max_retries, resp.status_code)
                if attempt < max_retries - 1:
                    await asyncio.sleep(2 ** attempt)
                    continue
                return False

            try:
                body = resp.json()
            except ValueError:
                logger.warning("call trace send failed: invalid json response")
                if attempt < max_retries - 1:
                    await asyncio.sleep(2 ** attempt)
                    continue
                return False

            if int(body.get("ErrorCode", -1)) != 0:
                logger.warning("call trace send failed: body={}", body)
                if attempt < max_retries - 1:
                    await asyncio.sleep(2 ** attempt)
                    continue
                return False

            return True

        return False
