# WebSocket 改造问题修复计划

> 来源：2026-04-18 WebSocket 改造专项代码审查
> 状态追踪：每项修复完成后在文件末尾更新进度

## 优先级说明
- **P0**：Critical — 数据错误、安全问题、核心功能损坏
- **P1**：Important — 业务逻辑缺陷、潜在 bug
- **P2**：Minor — 性能优化、代码质量

---

## P0

### W-1：Flutter WebSocket 重连竞态 — `_isConnecting` 不重置
- **文件**：`huanxi/lib/services/websocket_service.dart:162-167`
- **问题**：`_onError` 不重置 `_isConnecting = false`。当连接在 `await _channel!.ready` 阶段失败时，`_isConnecting` 保持 true，导致后续 `connect()` 调用被 `if (_isConnecting) return;` guard 阻止，永久断连。
- **修复**：在 `_onError` 中添加 `_isConnecting = false`
- **状态**：TODO

---

### W-2：watchdog + `call_end` 双重推送 `call_ended` 事件
- **文件**：`backend/app/api/v1/app/call.py:796-805`
- **问题**：`call_end` 在 `status == "ended"` bypass 分支后（第 755-757 行），仍然执行 `asyncio.create_task(_ws_push_call_ended_to_peer(...))`（第 799-805 行）。当 watchdog 已关闭通话并推送了 `call_ended` 后，`call_end` 又推送一次，客户端收到两个结束事件。
- **修复**：将 WebSocket 推送移入 `if call_record.status != "ended"` 分支，仅在正常结束流程中推送
- **状态**：TODO

---

## P1

### W-3：`dialing` API 移除主播在线检查 — 已修复
- **文件**：`backend/app/api/v1/app/call.py:248-256`
- **决策**：不允许呼叫离线主播
- **修复**：在主播查询后添加 `if not anchor.is_online: return Fail(code=400, msg="主播当前不在线，请稍后再试")`
- **状态**：✅ DONE（commit `45c84ea`）

---

### W-4：Redis Pub/Sub fire-and-forget — 关键事件无监控
- **文件**：`backend/app/websocket/manager.py`
- **问题**：`push_to_user` 使用 `redis.publish()`，Redis 不可用或无订阅者时静默失败，无监控告警。
- **修复**：为关键事件（`call_ended`、`balance_empty` 等）添加 `critical=True` 参数，失败时记录 WARNING 日志用于监控
- **状态**：TODO

---

### W-5：watchdog follower 无退避竞争
- **文件**：`backend/app/core/call_watchdog.py:369-371`
- **问题**：leader 崩溃后多个 follower 同时竞争，无退避机制增加 Redis 操作。
- **修复**：竞争失败后添加随机退避 `random.uniform(1, 5)`
- **状态**：TODO

---

### W-6：通话时长本地计时漂移
- **文件**：`huanxi/lib/modules/call/call_room_page.dart`
- **问题**：本地计时与后端计费逐渐漂移，可能影响续费逻辑。
- **修复**：`_renewLeaseWithRetry` 成功后用服务端时长同步本地计时器
- **状态**：TODO

---

## P2

### W-7：CallTraceService Lua SHA 缓存无 fallback 恢复
- **文件**：`backend/app/services/call_trace_service.py`
- **问题**：`evalsha` 失败（NOSCRIPT）后每次 append 走 fallback 而非重新 `script_load`。
- **修复**：检测 NOSCRIPT 错误后重新 `script_load`
- **状态**：TODO

---

### W-8：缺少 WebSocket 集成测试
- **文件**：`backend/tests/test_websocket_manager.py`（新建）
- **问题**：只有单元测试，WebSocket 推送链路无自动化验证。
- **修复**：用 `pytest-asyncio` + mock Redis 验证 `push_to_user` -> `publish` -> `_send_ws` 链路
- **状态**：TODO

---

## 已审查确认无问题（无需修复）

以下审查中的问题经代码核实后确认为误报：

| 审查项 | 文件 | 审查结论 |
|--------|------|----------|
| `InsufficientBalanceException` 未定义 | `call_room_page.dart` | ✅ 已正确定义在 `api_exception.dart`，import 存在（第14行） |
| `_handleWsIncomingCall` 是轮询非 WebSocket | `main_shell.dart:339-376` | ✅ WebSocket handler 已直接导航（第368-369行），`flag` 去重是设计选择 |
| IM SDK `_currentUserId` 状态不一致 | `im_service.dart:143-166` | ✅ `_currentUserId = userId`（第160行）在 `if (loginRes.code != 0)` 之后，成功后才设置 |
| `_onDone` 缺少 `_isConnecting = false` | `websocket_service.dart:169-178` | ✅ `_onDone` 不在 `connect()` 成功路径被调用，不会阻止重连 |

---

## 进度

| # | 标签 | 描述 | 优先级 | 状态 | 提交 |
|---|------|------|--------|------|------|
| 1 | W-1 | WebSocket 重连竞态 `_isConnecting` | P0 | DONE | |
| 2 | W-2 | `call_end` 双重推送 `call_ended` | P0 | DONE | |
| 3 | W-3 | `dialing` API 移除主播在线检查 | P1 | ✅ DONE | `45c84ea` |
| 4 | W-4 | Redis Pub/Sub 关键事件无监控 | P1 | DONE | |
| 5 | W-5 | watchdog follower 无退避 | P1 | DONE | |
| 6 | W-6 | 通话时长本地计时漂移 | P1 | DONE | |
| 7 | W-7 | CallTraceService Lua SHA 无恢复 | P2 | DONE | |
| 8 | W-8 | 缺少 WebSocket 集成测试 | P2 | DONE | |

---

## W-1 修复详情

**文件**: `huanxi/lib/services/websocket_service.dart:162-167`

**修复内容**: 在 `_onError` 中添加 `_isConnecting = false`

**修复前**:
```dart
void _onError(Object error) {
    debugPrint('[Ws] 连接错误: $error');
    _authenticated = false;
    _channel = null;
    _scheduleReconnect();
}
```

**修复后**:
```dart
void _onError(Object error) {
    debugPrint('[Ws] 连接错误: $error');
    _isConnecting = false;  // ← 新增
    _authenticated = false;
    _channel = null;
    _scheduleReconnect();
}
```

---

## W-2 修复详情

**文件**: `backend/app/api/v1/app/call.py:796-805`

**修复内容**: 将 `_ws_push_call_ended_to_peer` 调用移入 `else` 分支，仅在本地处理通话结束时推送，避免 watchdog 已推送后重复推送。

**修复前**: 推送在 `if/else` 分支外部，无条件推送
**修复后**: 推送在 `else` 分支内部，仅正常结束流程推送

---

## W-4 修复详情

**文件**: `backend/app/websocket/manager.py`

**修复内容**:
1. `ConnectionManager` 新增 `_CRITICAL_EVENTS = frozenset({...})` 类属性
2. `push_to_user` 新增 `critical=False` 参数，关键事件失败时记录 `WARNING` 日志
3. `events.py` 中关键事件函数 (`push_call_ended`, `push_call_timeout`, `push_call_balance_empty`, `push_balance_update`, `push_presence`) 均传递 `critical=True`
4. `call.py` 中 `_ws_push_call_ended_to_peer` 传递 `critical=True`

---

## W-5 修复详情

**文件**: `backend/app/core/call_watchdog.py`

**修复内容**: `import random` 并将 follower 竞争失败后的 `await asyncio.sleep(5)` 改为 `await asyncio.sleep(random.uniform(1, 5))`

---

## W-7 修复详情

**文件**: `backend/app/services/call_trace_service.py`

**修复内容**: `_default_idempotency_claimer` 中捕获 `redis.exceptions.ResponseError`，检测到 NOSCRIPT 后重新 `script_load` 并重试 evalsha。

---

## W-6 修复详情

**文件**: `huanxi/lib/modules/call/call_room_page.dart`

**修复内容**: `_renewLeaseWithRetry` 成功后，用服务端时长 `duration` 同步 `_callStartTime`（倒推锚点），避免本地计时漂移累积。

---

## W-8 修复详情

**文件**: `backend/tests/test_websocket_manager.py`（新建）

**修复内容**: 使用 `pytest` + `pytest-asyncio` + mock Redis 验证：
- 在线用户推送成功（调用 redis.publish）
- 离线用户推送跳过
- 关键事件失败记录 WARNING 日志
- PubSub 消息路由到正确的 worker
- 关键事件集合标记正确
