# 通话页拆分重构优化方案（替换版）

> 日期：2026-04-18
> 状态：已评审通过，待实施

## 摘要

- 目标：在不改变现有业务行为与路由参数的前提下，完成通话模块职责拆分，覆盖 `room + outgoing + incoming`，降低后续维护风险。
- 并行子方案纳入：整合 `docs/superpowers/plans/2026-04-19-ws-force-exit-settlement.md`，统一处理 WS 强退兜底与按强退时间结算，避免前后端在同一文件反复冲突。
- 已校正的现状基线：
  - `call_room_page.dart` 实际约 **1056 行**（非 400）。
  - `call_outgoing_page.dart` 实际约 **418 行**，当前并无 RTC 逻辑。
  - `incoming_call_page.dart` 实际约 **312 行**（非 100）。
  - WS 真实事件应以当前代码/后端为准：`gift_received`、`call_balance_empty`、`balance_updated`、`call_ended/call_timeout/call_cancelled/call_rejected`，不使用 `gift_sent/call_hung_up`。
  - 连接层与来电入口已做可靠性补丁：`WsService` 新增 ready/auth 超时与旧连接回调隔离；`main_shell` 已调整来电路由互斥逻辑；`call_room_page` 新增 RTC 对端离线超时兜底结束（`peer_left`）。
- 已确认边界：
  - 输出完整替换版方案。
  - `incoming` 一并纳入治理。
  - `call_room` 采用严格 4 Controller 拆分。
  - 不强制行数指标。
  - 验收以手工回归为主。

## 关键实现变更

### 与 `2026-04-19-ws-force-exit-settlement` 的整合约束

- 统一协议：客户端通话中发送 `call_heartbeat`；服务端以 `last_seen` 判定离场并结算。
- 统一结束原因口径：前端事件映射需兼容 `force_exit`（服务端强退结算语义）与 `peer_left`（RTC 离线兜底语义）。
- 冲突优先级：同一行为优先采用后端结算口径，前端仅做展示与退出，不在前端固化计费规则。
- 共享文件冲突面：
  - `huanxi/lib/services/websocket_service.dart`：连接稳定性改造与 `sendCallHeartbeat` 能力必须共存。
  - `huanxi/lib/modules/call/call_room_page.dart`：RTC 离线兜底、WS 心跳启停、页面退出门禁必须共存。
  - `backend/app/core/call_watchdog.py` 与 `backend/app/api/v1/app/call.py`：强退结算与手动挂断并发幂等需统一。

### 变更文件范围（核心）

- `huanxi/lib/modules/call/call_room_page.dart`
- `huanxi/lib/modules/call/call_outgoing_page.dart`
- `huanxi/lib/modules/call/incoming_call_page.dart`
- `huanxi/lib/modules/call/controllers/*`（新增）
- `huanxi/lib/modules/call/call_event_mapper.dart`（新增，事件/结束原因统一映射）
- `huanxi/lib/services/websocket_service.dart`（已存在稳定性改造，重构需兼容）
- `huanxi/lib/modules/home/main_shell.dart`（已存在来电路由互斥改造，重构需兼容）
- `backend/app/core/call_presence.py`（按子方案新增，存储通话双方 last_seen）
- `backend/app/websocket/router.py`（按子方案扩展 `call_heartbeat`）
- `backend/app/core/call_watchdog.py`（按子方案引入强退判定与按 last_seen 结算）
- `backend/app/api/v1/app/call.py`（按子方案保持与 watchdog 并发幂等）
- `backend/app/models/admin.py` 与 Aerich 迁移（按子方案新增强退结算审计字段）

### call_room 四控制器

- `CallRtcController`：Agora 生命周期与媒体控制（init/join/leave/release/toggle/flip）。
- `CallWsController`：仅负责订阅 WS 与连接状态，按 `call_id` 过滤并分发。
- `CallSessionNotifier`：通话状态机（`idle/connecting/ongoing/ending/ended`）、本地时长计时、结束流程门禁（防重入）。
- `CallGiftController`：礼物动画显隐状态。

### 控制器通信规则（防循环依赖）

- `CallWsController` 只通过 `ref.read(...notifier)` 调用 `Session/Gift/Auth`，不持有对方实例字段。
- `CallSessionNotifier` 不直接依赖 `RtcController`，只产出“结束意图状态”；页面层 `ref.listen` 触发 `RtcController.leaveAndRelease()` 与路由退出。
- `balance_updated` 继续走 `authProvider.syncBalance`，保持全局余额刷新通道一致。

### outgoing + incoming 同步治理

- 新增共享映射/倒计时工具（`CallEventMapper + CallCountdownController`），统一结束原因判定与 30 秒倒计时行为。
- `CallOutgoingController` 与 `CallIncomingController` 各自管理本页状态，但复用统一 WS 事件判定与关闭流程，消除重复逻辑分叉。

### 保持不变项（强约束）

- 路由 query 参数与页面入参不改。
- 后端 API 协议不改。
- 不新增依赖/配置/额外功能。

## 对外接口与类型调整

### Provider

- `callRtcControllerProvider`
- `callWsControllerProvider`
- `callSessionProvider`
- `callGiftControllerProvider`
- `callOutgoingControllerProvider`
- `callIncomingControllerProvider`

### 状态类型

- `CallSessionState`：`callId/phase/endReason/callDuration/isEndingForBalance/...`
- `CallGiftState`：`isShowing/giftName/giftIcon/giftPrice/senderNickname`
- `CallOutgoingState`、`CallIncomingState`：`leftSeconds/isActionInFlight/isPageClosing/errorMessage/...`

### 统一事件映射

- 输入：WS `event + data`
- 输出：`CallEndReason`（`rejected/timeout/cancelled/balance_empty/network_lost/peer_left/force_exit/normal`）及是否触发本地 toast/退出动作

### WS 心跳接口契约（新增）

- 客户端：
  - `WsService` 提供 `sendCallHeartbeat({required int callId})`。
  - 通话建立后 1s 周期发送，离开房间或结束通话立即停止。
- 服务端：
  - WS 路由接收 `call_heartbeat`，以服务端身份关系校验参与者身份，不信任客户端 role。
  - watchdog 使用 `last_seen + grace` 计算 `effective_ended_at`，并作为强退结算依据。
- 兼容要求：
  - 不影响现有 `balance_updated`、`call_ended`、`call_balance_empty` 事件处理链路。
  - 重构后的 `CallWsController`/`CallSessionNotifier` 需承接心跳启停逻辑，避免回退到页面散落定时器。

### 删除不一致描述

- 移除 `call_hung_up`、`gift_sent`、`_renewLeaseWithRetry` 在本次 Flutter 方案中的职责描述（当前代码路径无此逻辑）。

## 分阶段迁移（无行为漂移）

### 1. 基线冻结阶段

- 提取当前三页行为矩阵（事件 -> UI/路由/API 动作），作为迁移核对清单。
- 先引入 `CallEventMapper` 与共享倒计时工具，不改页面对外行为。
- 冻结 WS 心跳协议与结束原因字典（包含 `force_exit`、`peer_left`），作为前后端联调基线。

### 2. call_room 控制器化阶段

- 落四控制器骨架与状态类型。
- 将 RTC/WS/Session/Gift 逻辑从页面迁移到控制器。
- 页面改为“渲染 + 用户交互分发 + side-effect 监听”。
- 在该阶段纳入 `call_heartbeat` 启停控制，避免后续二次改动 `call_room_page.dart`。

### 3. outgoing + incoming 同步治理阶段

- 引入两个页面控制器，复用统一事件/倒计时逻辑。
- 保持原跳转链路不变（outgoing accepted -> room，incoming accept -> room）。

### 4. 服务端强退结算联动阶段（并行可执行）

- 落地 Redis `call_presence`、WS `call_heartbeat`、watchdog 强退判定与 `effective_ended_at` 结算逻辑。
- 对齐 `/call/end` 与 watchdog 并发幂等，确保仅一次有效结算。
- 补齐强退相关回归用例（时间点、并发、金额守恒）。

### 5. 收口阶段

- 清理页面私有重复方法与废弃字段。
- 更新文档中的真实行数、事件名、模块职责图。

## 手工回归测试清单（本次验收标准）

### 主叫流程

- 发起呼叫成功 -> 倒计时运行 -> 对方接听 -> 正常进入房间。
- 发起后对方拒绝/超时/取消 -> 正确 toast + 退出。

### 被叫流程

- 收到来电 -> 接听进入房间。
- 拒绝来电 -> 正确退出，无残留订阅。

### 房间流程

- `call_ended/call_timeout/call_cancelled/call_rejected/call_balance_empty` 分别触发正确文案与退出。
- `balance_updated` 可刷新全局余额展示。
- `gift_received` 动画展示与自动消失正常。
- WS 断连超过 10 秒触发 `network_lost` 退出逻辑。
- RTC `onUserOffline` 后超过 8 秒仍未恢复，触发 `peer_left` 兜底退出逻辑。
- 服务端强退时，客户端收到 `force_exit` 语义后正确退出且文案一致。
- 强杀场景费用按 `last_seen` 时间点结算，不因 watchdog 检测延迟多扣。

### 资源释放

- 页面返回/挂断/异常退出后，Timer 与 WS 订阅释放，无重复回调。
- RTC `leave + release` 仅执行一次，不出现重入报错。

## 假设与默认值

- 默认继续使用现有 `WsService` 全局单例模式，并保留已落地的连接稳定性改造（ready/auth timeout、单连接回调隔离、异常 ping 主动触发重连）。
- 默认不新增自动化测试文件；验收以手工回归清单通过为准。
- 默认不回退 `main_shell` 已落地的来电入口互斥改造；新控制器需与其兼容。
- 默认接入 `2026-04-19-ws-force-exit-settlement` 子方案中的心跳协议与强退结算语义，前端只做状态与展示适配，不新增本地计费规则。
- 默认优先“行为零回归”，其次再做进一步 UI 组件化瘦身。
