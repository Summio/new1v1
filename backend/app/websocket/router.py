"""WebSocket 路由。

端点：/ws/app
认证：连接后接收首帧 {"type":"auth","token":"..."}，调用 app_auth.is_app_authed 验证
心跳：30 秒无消息则关闭连接，收到 {"type":"ping"} 回复 {"type":"pong"}
"""

from __future__ import annotations

import asyncio
import json
import time
from typing import Any

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from starlette.websockets import WebSocketState

from app.core.app_auth import is_app_authed
from app.core.call_presence import update_last_seen
from app.log import logger
from app.models import CallRecord
from app.websocket.manager import get_manager

router = APIRouter()

# ===== 常量 =====

_AUTH_TIMEOUT = 30  # 秒，等待认证的超时时间
# 心跳超时必须显著大于客户端 ping 间隔，避免网络抖动下误判离线导致关键事件丢失
_HEARTBEAT_TIMEOUT = 75  # 秒，无消息则认为断开
_PING_INTERVAL = 20  # 客户端心跳间隔（秒）


# ===== WebSocket 端点 =====


@router.websocket("/ws/app")
async def ws_app(websocket: WebSocket) -> None:
    """App 用户 WebSocket 连接端点。

    协议流程：
      1. client 连接（websocket.accept）
      2. client 发送 {"type": "auth", "token": "jwt..."}
      3. server 验证，发送 {"type": "auth_success", "user_id": N} 或 {"type": "error", "code": 401, ...}
      4. 保持连接，接收消息（目前仅处理 ping）
      5. 30 秒无消息则关闭连接
    """
    manager = get_manager()

    # 启动 Pub/Sub 监听（每个 worker 只执行一次）
    await manager.start_pubsub()

    # 接受连接
    await websocket.accept()

    user_id: int | None = None

    try:
        # ===== 阶段 1：等待认证 =====
        try:
            raw = await asyncio.wait_for(
                websocket.receive_json(),
                timeout=_AUTH_TIMEOUT,
            )
        except asyncio.TimeoutError:
            logger.warning("[WS] auth timeout")
            await _send_error(websocket, 401, "认证超时")
            await websocket.close(code=4001)
            return

        msg = _parse_message(raw)
        if msg is None or msg.get("type") != "auth":
            await _send_error(websocket, 400, "首帧应为 auth")
            await websocket.close(code=4002)
            return

        token = msg.get("token", "")
        if not token:
            await _send_error(websocket, 400, "token 不能为空")
            await websocket.close(code=4002)
            return

        # 验证 JWT
        app_user = await is_app_authed(token)
        if app_user is None:
            await _send_error(websocket, 401, "Token无效或已过期")
            await websocket.close(code=4001)
            return

        user_id = int(app_user.id)
        await manager.connect(user_id, websocket)
        await websocket.send_json({"type": "auth_success", "user_id": user_id})
        logger.info(f"[WS] user {user_id} authenticated successfully")

        # ===== 阶段 2：保持连接，接收消息 =====
        while True:
            try:
                raw = await asyncio.wait_for(
                    websocket.receive_json(),
                    timeout=_HEARTBEAT_TIMEOUT,
                )
            except asyncio.TimeoutError:
                # 30 秒无消息，判定为超时
                logger.debug(f"[WS] user {user_id} heartbeat timeout")
                break

            msg = _parse_message(raw)
            if msg is None:
                continue

            msg_type = msg.get("type", "")

            if msg_type == "ping":
                try:
                    await websocket.send_json({"type": "pong"})
                except Exception:
                    break

            elif msg_type == "subscribe":
                # 当前设计无需订阅，所有事件按用户推送
                # 保留接口以便未来扩展
                pass

            elif msg_type == "set_online_status":
                # 手动切换在线状态（不影响 WS 连接）
                online = bool(msg.get("online", True))
                try:
                    from app.websocket.presence import (
                        broadcast_presence,
                        clear_manual_offline,
                        set_manual_offline,
                    )

                    if online:
                        await clear_manual_offline(user_id)
                    else:
                        await set_manual_offline(user_id)
                    await broadcast_presence(manager=manager, user_id=user_id, online=online)
                    await websocket.send_json({"type": "online_status_ack", "online": online})
                except Exception as e:
                    logger.warning(f"[WS] set_online_status failed for {user_id}: {e}")
                    await _send_error(websocket, 500, "状态切换失败")

            elif msg_type == "call_heartbeat":
                ok = await _handle_call_heartbeat_message(
                    user_id=int(user_id),
                    msg=msg,
                )
                if not ok:
                    await _send_error(websocket, 403, "心跳无效或无权限")

            else:
                # 忽略其他消息类型
                pass

    except WebSocketDisconnect:
        logger.info(f"[WS] user {user_id} disconnected normally")

    except Exception as e:
        logger.warning(f"[WS] user {user_id} error: {e}")

    finally:
        # 清理连接
        if user_id is not None:
            # 必须携带当前 websocket，避免旧连接迟到断开时把新连接一并清掉
            await manager.disconnect(user_id, websocket=websocket)

        # 确保 WebSocket 正确关闭
        try:
            if websocket.client_state == WebSocketState.CONNECTED:
                await websocket.close()
        except Exception:
            pass


# ===== 辅助函数 =====


def _parse_message(raw: Any) -> dict | None:
    """解析 JSON 消息，失败返回 None。"""
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return None
    return None


async def _send_error(websocket: WebSocket, code: int, msg: str) -> None:
    """发送错误消息。"""
    try:
        await websocket.send_json({"type": "error", "code": code, "msg": msg})
    except Exception:
        pass


def _now_ms() -> int:
    return int(time.time() * 1000)


async def _handle_call_heartbeat_message(*, user_id: int, msg: dict[str, Any]) -> bool:
    call_id_raw = msg.get("call_id")
    try:
        call_id = int(call_id_raw)
    except (TypeError, ValueError):
        return False
    if call_id <= 0:
        return False

    call_record = await CallRecord.filter(id=call_id, status="ongoing").first()
    if call_record is None:
        return False

    role: str
    if int(call_record.caller_id) == int(user_id):
        role = "caller"
    elif int(call_record.callee_id) == int(user_id):
        role = "callee"
    else:
        return False

    # role 由服务端关系推断，不信任客户端上报 role 字段。
    await update_last_seen(
        call_id=call_id,
        user_id=int(user_id),
        role=role,
        now_ms=_now_ms(),
    )
    return True
