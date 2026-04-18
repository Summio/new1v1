# Flutter 通话页面拆分重构设计方案

> 日期：2026/04/18
> 状态：草稿，待评审

## 1. 背景与目标

### 1.1 问题

`call_room_page.dart` 当前约 400 行，承担了 7 个不同职责：

1. **RTC 引擎管理** — Agora `RtcEngine` 初始化、事件监听、开关摄像头/麦克风/扬声器、画面翻转
2. **WebSocket 事件处理** — 订阅 `WsService.events` 流，处理 `call_ended` / `call_timeout` / `balance_updated` 等事件
3. **通话计时** — `_durationTimer` 本地计时 + `_callStartTime` 同步
4. **通话续费** — `_renewLeaseWithRetry` 调用后端续费接口
5. **通话控制** — 结束通话逻辑（主动挂断 / 余额耗尽 / 对方挂断）
6. **礼物动画状态** — `_giftShowing` 等字段驱动礼物弹窗 UI
7. **连接状态监控** — `WsConnectionEvent` 流处理断连计时器

同一文件中混杂了引擎调用、API 调用、状态管理、UI 构建四种完全不同层次的概念，导致：

- 单文件过长，难以定位和修改
- 难以单独测试某个功能
- 多人协作时冲突频繁

### 1.2 目标

- 将 `call_room_page.dart` 拆分为多个职责单一的 Controller/Notifier
- 通过 Riverpod Provider 链实现模块间通信
- 保持外部行为不变（UI 表现、API 调用结果一致）
- 验证拆分模式后，推广到 `call_outgoing_page`

## 2. 架构设计

### 2.1 整体架构

```
CallRoomPage (View)
  ├── ref.watch(CallRtcController)       → RTC 引擎管理
  ├── ref.watch(CallWsController)        → WS 事件订阅与分发
  ├── ref.watch(CallSessionNotifier)     → 会话状态 + 计时 + 续费
  └── ref.watch(CallGiftController)      → 礼物动画状态

wsService (全局单例)  ──→  CallWsController  ──→  各 Controller

authProvider (全局)  ←──  CallWsController (balance_updated)
```

**设计原则：**
- View 只负责 UI 渲染和用户交互分发
- Controller 持有独立状态，通过 `ref.watch` 互相感知
- 不引入 Event Bus，保持与项目中 `auth_provider.dart` / `anchor_provider.dart` 等一致的 Riverpod 模式
- `balance_updated` 等全局事件走已有 `authProvider` 通道

### 2.2 模块职责

#### CallRtcController (`controllers/call_rtc_controller.dart`)

负责 Agora RTC 引擎的完整生命周期。

**状态（全部字段）：**
- `RtcEngine? _engine` — RTC 引擎实例
- `int? _localUid` — 本地用户 UID
- `int? _remoteUid` — 远端用户 UID
- `bool isMicOn` / `isSpeakerOn` / `isCameraOn` / `isFlipping` — 媒体控制
- `bool isJoined` — 是否已加入频道

**方法：**
- `Future<void> initEngine()` — 初始化 RTC 引擎，注册事件监听
- `Future<void> joinChannel(int uid, String channelName)` — 加入频道
- `Future<void> leaveChannel()` — 离开频道
- `Future<void> dispose()` — 销毁引擎
- `void toggleMic()` / `toggleSpeaker()` / `toggleCamera()` / `flipCamera()`
- `void onRemoteUserJoined(int uid)` — 远端用户加入回调
- `void onRemoteUserLeft(int uid)` — 远端用户离开回调
- `void onConnectionStateChanged(state)` — 连接状态变化回调

**依赖：** `RtcEngine`（Agora SDK）

#### CallWsController (`controllers/call_ws_controller.dart`)

负责 WebSocket 订阅和事件分发到其他 Controller。

**状态：**
- `bool isWsConnected` — WS 连接状态
- `StreamSubscription? _wsSubscription` — WS 事件订阅
- `StreamSubscription? _wsConnectionSubscription` — WS 连接状态订阅

**方法：**
- `void init(WebSocketService ws, CallSessionNotifier session, CallGiftController gift)` — 初始化，注入依赖
- `void dispose()` — 取消订阅
- `_onWsEvent(WsEvent event)` — 事件分发：
  - `call_ended` → `session.endCall(reason)`
  - `call_timeout` → `session.endCall(reason: 'timeout')`
  - `call_rejected` → `session.endCall(reason: 'rejected')`
  - `call_hung_up` → `session.endCall(reason: 'hung_up')`
  - `balance_updated` → `authProvider.syncBalance()`
  - `gift_sent` → `gift.showGift(data)`
  - `call_accepted` → `session.onCallAccepted()`
- `_onWsConnectionEvent(WsConnectionEvent event)` — 连接状态处理

**依赖：** `WsService`（全局单例）、`CallSessionNotifier`、`CallGiftController`、`authProvider`

#### CallSessionNotifier (`controllers/call_session_controller.dart`)

负责通话会话状态、计时器和续费逻辑。

**状态（继承 StateNotifier<CallSessionState>）：**
- `CallSessionState`：
  - `int? callId`
  - `String peerUserId` / `String peerName` / `String? anchorId`
  - `Duration callDuration = Duration.zero`
  - `DateTime? callStartTime`
  - `bool isEnding = false`
  - `bool isEndingForBalance = false`
  - `String? endReason`
  - `bool isJoined = false`

**方法：**
- `void init({required int callId, ...})` — 初始化会话参数
- `void onCallJoined()` — RTC join 成功后调用，启动计时器
- `void onCallAccepted()` — 对方接听，启动计时器
- `void endCall({String? reason})` — 结束通话，停止计时器
- `void _startTimer()` — 内部：启动 `_durationTimer`，每秒更新 `callDuration`
- `void _syncCallStartTime(int serverDuration)` — 用服务端时长同步计时器锚点（W-6 已实现）
- `Future<void> _renewLeaseWithRetry()` — 内部：调用续费 API
- `void dispose()` — 清理计时器

**依赖：** `DioClient`、`authProvider`

#### CallGiftController (`controllers/call_gift_controller.dart`)

负责礼物动画状态。

**状态（继承 StateNotifier<GiftAnimationState>）：**
- `GiftAnimationState`：
  - `bool isShowing = false`
  - `String giftName`
  - `String giftIcon`
  - `int giftPrice`
  - `String senderNickname`

**方法：**
- `void showGift(Map<String, dynamic> data)` — 显示礼物动画
- `void hideGift()` — 隐藏礼物动画

#### CallRoomPage (`modules/call/call_room_page.dart`)

重构后的 View 层，仅保留 UI 布局。

**职责：**
- `_CallRoomPageState` 仅持有 `WidgetRef ref`
- `build()` 方法中组合 4 个 Controller 的状态
- 用户交互调用对应 Controller 方法（`ref.read(CallRtcController.provider).toggleMic()`）
- `initState` 中初始化 4 个 Controller
- `dispose` 中销毁 4 个 Controller
- 礼物面板 `GiftPanel` 改为从 `CallGiftController` 读取状态

**文件行数目标：**< 150 行（当前 ~400 行）

### 2.3 通信协议

```
CallWsController → CallSessionNotifier
  endCall({reason: String?})
  onCallAccepted()

CallWsController → CallGiftController
  showGift(data: Map<String, dynamic>)

CallWsController → authProvider (全局)
  syncBalance(coins: int, diamonds: int)

CallSessionNotifier → CallRtcController (隐式，通过状态)
  CallRtcController 被 CallRoomPage watch，
  CallSessionNotifier.isEnding 变化时 CallRoomPage 触发 leaveChannel()

CallRoomPage (View 协调层)
  用户点击挂断 → ref.read(CallSessionNotifier.endCall())
  用户点击接听 → ref.read(CallRtcController.joinChannel())
```

## 3. call_outgoing_page 拆分

### 3.1 当前状态

`call_outgoing_page.dart` 约 250 行，包含：

- RTC 引擎初始化
- 去电 API 调用（`call_create`）
- Agora channel join
- WS 监听（对方接听 / 拒接 / 挂断）
- 30 秒倒计时
- UI 布局

### 3.2 拆分方案

| 模块 | 文件 | 职责 |
|------|------|------|
| `CallOutgoingNotifier` | `controllers/call_outgoing_controller.dart` | RTC 引擎初始化/销毁、去电 API 调用、Agora join、WS 监听（接听/拒接/挂断/超时）、倒计时 |
| `call_outgoing_page.dart` | `modules/call/call_outgoing_page.dart` | 仅保留来电等待 UI + 用户交互 |

**为什么不拆成更多？**
RTC 和 API 调用逻辑紧密耦合于同一个操作流程（创建 → join → 等待 → 确认）。强行拆开会增加 Controller 间通信复杂度。`CallOutgoingNotifier` 单一模块即可，职责内聚，测试简单。

### 3.3 CallOutgoingNotifier 设计

**状态（继承 StateNotifier<CallOutgoingState>）：**
- `CallOutgoingState`：
  - `int? callId`
  - `bool isLoading`
  - `bool isRinging` — 对方响铃中
  - `bool isJoined` — 是否已加入 RTC 频道
  - `int leftSeconds = 30` — 剩余倒计时秒数
  - `String? errorMessage`

**方法：**
- `Future<bool> initAndCreateCall(...)` — 初始化 RTC + 调用去电 API
- `Future<void> _joinChannel()` — 加入 Agora 频道
- `Future<void> _onCallAccepted()` — 对方接听，跳转通话房间
- `Future<void> _onCallRejected()` — 对方拒接，清理并退出
- `Future<void> _onCallHungUp()` — 对方挂断，清理并退出
- `Future<void> _onCallTimeout()` — 30 秒超时，清理并退出
- `Future<void> cancelCall()` — 用户主动取消
- `void dispose()` — 清理

## 4. incoming_call_page 处理

`incoming_call_page.dart` 当前约 100 行，包含：

- 来电弹窗 UI
- 30 秒倒计时
- 接听 / 拒接按钮
- WS 监听（对方取消）

**结论：暂不拆分**。100 行的单一职责页面，继续拆分反而增加文件数量但收益极低。

## 5. API 变更

### 5.1 新增 Provider 文件

```
huanxi/lib/modules/call/controllers/
  ├── call_rtc_controller.dart      # CallRtcController + Provider
  ├── call_ws_controller.dart        # CallWsController + Provider
  ├── call_session_controller.dart  # CallSessionNotifier + Provider
  └── call_gift_controller.dart     # CallGiftController + Provider

huanxi/lib/modules/call/controllers/
  └── call_outgoing_controller.dart  # CallOutgoingNotifier + Provider
```

### 5.2 移除 / 简化现有文件

- `call_room_page.dart` — 从 ~400 行缩减到 < 150 行
- `call_outgoing_page.dart` — 从 ~250 行缩减到 < 100 行
- `incoming_call_page.dart` — 保持不变

### 5.3 路由参数不变

所有 query 参数传递方式保持不变：
- `call_room_page.dart` 通过 query 参数获取 `callId` / `peerUserId` 等
- `call_outgoing_page.dart` 同上

## 6. 迁移策略

采用**平行迁移**策略，分 3 步执行，每步后手动测试主流程。

### 第一步：创建 Controller 骨架（不改变行为）

1. 创建 `call_rtc_controller.dart`、`call_ws_controller.dart`、`call_session_controller.dart`、`call_gift_controller.dart`
2. Controller 内部方法暂时委托给原有 `_CallRoomPageState` 逻辑
3. `call_room_page.dart` 暂时不调用新 Controller

**验证：** `flutter analyze` 无新增告警。

### 第二步：迁移状态到 Controller（UI 行为不变）

1. 将 `_CallRoomPageState` 中的字段迁移到对应 Controller 的状态
2. 将 `_CallRoomPageState` 中的方法体迁移到 Controller
3. UI 层改为 `ref.watch(Controller.provider)` 读取状态，`ref.read()` 调用方法
4. 确保 `_durationTimer`、`StreamSubscription` 等在 Controller `dispose` 中正确清理

**验证：**
- 发起通话 → 接听 → 通话 30 秒 → 结束，全流程正常
- WebSocket 断连重连正常
- 礼物发送动画正常

### 第三步：拆分 call_outgoing_page

1. 创建 `call_outgoing_controller.dart`
2. 将 `call_outgoing_page.dart` 中的状态和方法迁移
3. 验证去电流程正常

## 7. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 迁移过程中行为不一致 | 高 | 每步后手动测试完整通话流程 |
| `StreamSubscription` 生命周期泄漏 | 中 | 所有 `dispose` 方法中 `cancel()` 订阅 |
| Controller 之间循环引用 | 低 | 通过 `WidgetRef` 注入，避免直接持有对方实例 |
| `agora_rtc_engine` 引擎单例状态冲突 | 中 | 每个 Controller 持有独立引擎引用，确保 `leaveChannel` 后再销毁 |

## 8. 测试计划

### 单元测试

- `CallSessionNotifier` — 续费逻辑、计时器状态转换
- `CallGiftController` — 动画状态切换

### 集成测试

- 完整通话流程（手动）
- WS 断连重连（手动）

### Widget 测试

- `call_room_page.dart` — 验证 UI 在各状态下的渲染

## 9. 工作量估算

| 步骤 | 任务 | 预计改动文件数 |
|------|------|---------------|
| 第一步 | 创建 4 个 Controller 骨架 | +4 新文件 |
| 第二步 | 迁移 call_room_page (~400→150 行) | 修改 1 文件 |
| 第三步 | 拆分 call_outgoing_page (~250→100 行) | +1 新文件，修改 1 文件 |

**总增量：5 个新文件，2 个文件重构**
