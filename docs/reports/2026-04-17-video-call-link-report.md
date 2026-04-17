# 视频通话前后端全链路分析报告

- 生成日期: 2026-04-17
- 分析方式: 静态代码走查（未依赖线上环境）
- 覆盖范围: Flutter(`huanxi/`)、FastAPI(`backend/app/`)、管理端配置页(`backend/web/`)

## 1. 结论摘要

当前视频通话主链路已形成闭环，采用“状态轮询 + RTC 入会 + 续租扣费 + 结束结算 + Watchdog 兜底”模型。

核心路径:
1. 主叫发起 `POST /app/dialing`
2. 被叫轮询 `GET /app/call/incoming`
3. 接听后双方轮询 `GET /app/call/status`，状态进入 `ongoing`
4. 双方调用 `POST /app/rtc/token` 入 RTC 房间
5. 通话中按分钟触发 `POST /app/call/renew`
6. 挂断调用 `POST /app/call/end`
7. 后台 watchdog 异常兜底超时/断续费关闭通话

## 2. 端到端链路

### 2.1 前端入口

- 主叫发起: `AnchorDetailPage._openCall()` -> `ApiEndpoints.dialing`
  - 文件: `huanxi/lib/modules/home/anchor_detail_page.dart`
- 被叫来电: `MainShell._startIncomingPolling()` 每 3s 调 `callIncoming`
  - 文件: `huanxi/lib/modules/home/main_shell.dart`
- 通话房间: `CallRoomPage`
  - 每 2s 轮询 `callStatus`
  - `ongoing` 后获取 `rtcToken` 并入会
  - 本地计时达到下一个分钟边界触发 `callRenew`
  - 挂断/销毁时调用 `callEnd` 或 `callCancel`
  - 文件: `huanxi/lib/modules/call/call_room_page.dart`

### 2.2 后端 API 与状态机

通话 API 位于 `backend/app/api/v1/app/call.py`：

- `POST /dialing`
  - 校验主叫忙线、被叫忙线、拒绝保护期、余额门槛
  - 创建 `CallRecord(status=pending)`
- `GET /call/incoming`
  - 返回主播当前待接来电
- `GET /call/status`
  - 返回 `pending/ongoing/ended` 与 `end_reason`
- `POST /call/accept`
  - `pending -> ongoing`，记录 `connected_at`
- `POST /call/reject`
  - `pending -> ended(rejected)`
- `POST /call/cancel`
  - `pending -> ended(cancelled)`
- `POST /call/renew`
  - 依据 `duration` 与 `call_billing_free_seconds` 计算应扣分钟
  - 仅扣增量分钟（`due_minutes - deducted_minutes`）
  - 余额不足返回 `501` 并结束通话（`balance_empty`）
- `POST /call/end`
  - 结束结算，必要时做退款校正

状态机:

`pending -> ongoing -> ended`

常见 `end_reason`:

`rejected/cancelled/timeout/balance_empty/network_lost/normal`

### 2.3 RTC 鉴权与配置来源

- `POST /app/rtc/token` 位于 `backend/app/api/v1/app/rtc.py`
- 依赖系统配置:
  - `rtc_app_id`
  - `rtc_app_certificate`
  - `call_billing_free_seconds`
- `free_seconds_before_billing` 随 token 返回前端，前后端计费边界一致

### 2.4 后台兜底任务

`backend/app/core/call_watchdog.py` 周期执行:

- 关闭超时 `pending` 来电 (`timeout`)
- 关闭长时间未续费的 `ongoing` 通话 (`network_lost`)

启动路径:

- `backend/app/__init__.py` 的 `lifespan` 启动 `run_call_watchdog`

## 3. 风险项与处理状态

### R1 (P0) 通话内礼物目标 anchor_id 可能错位

风险:

- 通话页原先把 `user_id` 当作 `anchor_id` 传给礼物接口，可能导致送礼失败/误送。

本次处理:

- 已修复。
- 通话路由参数拆分为:
  - `peerUserId`（通话对端用户 ID）
  - `anchorId`（礼物目标主播 ID，可选）
- 送礼前优先用 `anchorId`，缺省时按 `peerUserId` 反查；仍无法确定则禁止送礼并提示。

### R2 (P0) Watchdog 下一次续费边界计算偏差

风险:

- 旧逻辑在 `deducted_minutes > 0` 时未叠加免计费偏移，可能提前判定 `network_lost`。

本次处理:

- 已修复。
- 统一为 `free_seconds_before_billing + deducted_minutes * 60`。

### R3 (P1) 通话响应字段语义错位（diamonds 实际承载 coins）

风险:

- 接口字段语义与业务货币不一致，易造成客户端误用。

本次处理:

- 已修复（不做旧兼容）。
- 通话相关响应统一为 `coins`，移除通话响应中的 `diamonds` 歧义字段。
- 前端续费逻辑仅读取 `coins`。

### R4 (P1) 来电可靠性依赖轮询

风险:

- 当前来电主要依赖前台轮询，后台推送（FCM/APNs/本地通知唤醒）链路未完整落地。

本次处理:

- 本次未改动（需独立迭代，涉及移动端通知权限、推送网关、幂等与埋点）。

### R5 (P2) 旧心跳概念残留造成认知负担

风险:

- 仓库存在部分“心跳”命名残留（配置/key/限流常量），与当前“续租扣费”主链路并存。

本次处理:

- 本次未做结构性删除（避免影响其他模块引用）；建议在下迭代统一清理与命名。

## 4. 验证场景清单（建议回归）

1. 主叫发起 -> 被叫接听 -> 双方入 RTC -> 自动续租扣费 -> 主动挂断结算。
2. 主叫发起后 30s 无人接听 -> 自动 `timeout`。
3. 被叫拒绝后保护期内再次呼叫 -> `429` 拦截。
4. 通话中余额不足 -> `501` + `balance_empty` 结束。
5. 通话中续费请求连续失败 -> 前端触发降级结束。
6. 一方掉线且续费超时 -> watchdog 标记 `network_lost`。
7. 通话中送礼 -> `anchor_id` 语义正确，避免 user_id/anchor_id 混淆。
8. 前台/后台来电处理差异验证。

## 5. 本次改动文件

- `backend/app/core/call_watchdog.py`
- `backend/app/schemas/app_api.py`
- `backend/app/api/v1/app/call.py`
- `huanxi/lib/app/routes/app_router.dart`
- `huanxi/lib/modules/home/anchor_detail_page.dart`
- `huanxi/lib/modules/home/main_shell.dart`
- `huanxi/lib/modules/call/call_room_page.dart`
- `backend/tests/test_call_watchdog_math.py`
