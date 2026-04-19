# WebSocket 强杀兜底结束与按强退时间结算 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不引入 HTTP 心跳兜底的前提下，实现纯 WebSocket 通话心跳，确保强杀 App 后自动结束通话，且扣费严格按“强退时间点”结算。

**Architecture:** 客户端通话页通过 WS 每秒上报 `call_heartbeat`，服务端将双方 last_seen 写入 Redis；watchdog 基于 last_seen + grace 判定强退并结束通话，`effective_ended_at` 使用 last_seen 时间而非检测时间；结算逻辑在事务内与现有 `deducted_amount` 做差额补扣/退款，保证金额守恒。

**Tech Stack:** Flutter (Riverpod + WebSocketChannel), FastAPI, Tortoise ORM, Redis, Aerich, Pytest。

---

### Task 1: 数据模型与迁移（强退结算审计字段）

**Files:**
- Modify: `backend/app/models/admin.py`
- Create: `backend/migrations/models/<timestamp>_add_force_exit_settlement_fields.py`
- Test: `backend/tests/test_call_record_force_exit_fields.py`

- [ ] **Step 1: 写失败测试（字段存在且可空）**

```python
# backend/tests/test_call_record_force_exit_fields.py
from app.models import CallRecord

def test_call_record_has_force_exit_fields():
    fields = CallRecord._meta.fields_map
    assert 'effective_ended_at' in fields
    assert 'end_basis' in fields
    assert 'force_exit_user_id' in fields
```

- [ ] **Step 2: 运行失败测试**

Run: `cd backend && pytest tests/test_call_record_force_exit_fields.py -q`
Expected: FAIL（缺失字段）

- [ ] **Step 3: 最小实现模型字段 + 迁移**

```python
# backend/app/models/admin.py (CallRecord)
effective_ended_at = fields.DatetimeField(null=True, description='结算使用的实际结束时间')
end_basis = fields.CharField(max_length=32, null=True, description='manual_end/force_exit/timeout/balance_empty')
force_exit_user_id = fields.IntField(null=True, description='先离场用户ID')
```

```bash
cd backend
aerich migrate --name add_force_exit_settlement_fields
aerich upgrade
```

- [ ] **Step 4: 复跑测试**

Run: `cd backend && pytest tests/test_call_record_force_exit_fields.py -q`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add backend/app/models/admin.py backend/migrations/models/*.py backend/tests/test_call_record_force_exit_fields.py
git commit -m "feat(call): add force-exit settlement audit fields"
```

### Task 2: Redis 通话在场状态服务（last_seen 存取）

**Files:**
- Create: `backend/app/core/call_presence.py`
- Test: `backend/tests/test_call_presence.py`

- [ ] **Step 1: 写失败测试（heartbeat 写入与读取）**

```python
# backend/tests/test_call_presence.py
import pytest

@pytest.mark.asyncio
async def test_update_and_read_last_seen(call_presence):
    await call_presence.update_last_seen(call_id=1, user_id=100, role='caller', now_ms=1700000000000)
    snap = await call_presence.get_snapshot(call_id=1)
    assert snap['caller_last_seen_ms'] == 1700000000000
```

- [ ] **Step 2: 运行失败测试**

Run: `cd backend && pytest tests/test_call_presence.py -q`
Expected: FAIL（模块/函数不存在）

- [ ] **Step 3: 最小实现 call_presence 服务**

```python
# backend/app/core/call_presence.py
# 核心函数：
# update_last_seen(call_id, user_id, role, now_ms)
# mark_left_candidate(call_id, role, now_ms)
# clear_left_candidate(call_id, role)
# get_snapshot(call_id) -> dict
```

- [ ] **Step 4: 复跑测试**

Run: `cd backend && pytest tests/test_call_presence.py -q`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add backend/app/core/call_presence.py backend/tests/test_call_presence.py
git commit -m "feat(call): add redis call presence store"
```

### Task 3: WebSocket 协议扩展 `call_heartbeat`

**Files:**
- Modify: `backend/app/websocket/router.py`
- Test: `backend/tests/test_websocket_router_call_heartbeat.py`

- [ ] **Step 1: 写失败测试（合法心跳更新 last_seen）**

```python
@pytest.mark.asyncio
async def test_call_heartbeat_updates_last_seen(ws_client, call_factory):
    call = await call_factory(status='ongoing', caller_id=1, callee_id=2)
    await ws_client.send_json({'type': 'call_heartbeat', 'call_id': call.id, 'role': 'caller'})
    # 断言 Redis 中 caller_last_seen_ms 有值
```

- [ ] **Step 2: 写失败测试（非参与者心跳被拒绝）**

```python
@pytest.mark.asyncio
async def test_call_heartbeat_reject_non_participant(ws_client, call_factory):
    call = await call_factory(status='ongoing', caller_id=1, callee_id=2)
    await ws_client.send_json({'type': 'call_heartbeat', 'call_id': call.id, 'role': 'caller'})
    # 断言返回 error 或无写入
```

- [ ] **Step 3: 运行失败测试**

Run: `cd backend && pytest tests/test_websocket_router_call_heartbeat.py -q`
Expected: FAIL

- [ ] **Step 4: 最小实现 WS 路由分支**

```python
# backend/app/websocket/router.py
elif msg_type == "call_heartbeat":
    # 校验 call_id
    # 校验 user_id 是 caller/callee
    # role 由服务端关系推断，忽略客户端 role 欺骗
    # 写 call_presence.update_last_seen(...)
```

- [ ] **Step 5: 复跑测试**

Run: `cd backend && pytest tests/test_websocket_router_call_heartbeat.py -q`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add backend/app/websocket/router.py backend/tests/test_websocket_router_call_heartbeat.py
git commit -m "feat(ws): add call_heartbeat handling"
```

### Task 4: Watchdog 强退判定与按 last_seen 结算

**Files:**
- Modify: `backend/app/core/call_watchdog.py`
- Modify: `backend/app/api/v1/app/call.py`
- Test: `backend/tests/test_call_watchdog_force_exit_settlement.py`

- [ ] **Step 1: 写失败测试（强退结束点等于 last_seen）**

```python
@pytest.mark.asyncio
async def test_force_exit_uses_last_seen_as_effective_end(call_factory, call_presence):
    call = await call_factory(status='ongoing')
    # 设 last_seen 为 T
    # 执行 watchdog 一轮
    # 断言 call.effective_ended_at == T
```

- [ ] **Step 2: 写失败测试（检测晚到不多扣费）**

```python
@pytest.mark.asyncio
async def test_force_exit_late_detection_not_overcharge(call_factory, call_presence):
    # 构造 T_last_seen 到 watchdog 检测有延迟
    # 断言费用按 T_last_seen 计算
```

- [ ] **Step 3: 运行失败测试**

Run: `cd backend && pytest tests/test_call_watchdog_force_exit_settlement.py -q`
Expected: FAIL

- [ ] **Step 4: 最小实现 watchdog 逻辑**

```python
# backend/app/core/call_watchdog.py
# 参数：
# call_presence_offline_detect_seconds=3
# call_presence_settle_grace_seconds=5
# 逻辑：
# 1) now-last_seen>detect -> 标记 left_candidate
# 2) 超过 grace 且未恢复 -> status=ended, end_basis='force_exit'
# 3) effective_ended_at=last_seen, ended_at=effective_ended_at
# 4) 费用按 effective_ended_at 重算，和 deducted_amount 对账
```

- [ ] **Step 5: 与 `/call/end` 并发保护对齐**

```python
# backend/app/api/v1/app/call.py
# 保持 select_for_update + status ended 直接返回，避免双重结算
```

- [ ] **Step 6: 复跑测试**

Run: `cd backend && pytest tests/test_call_watchdog_force_exit_settlement.py -q`
Expected: PASS

- [ ] **Step 7: 提交**

```bash
git add backend/app/core/call_watchdog.py backend/app/api/v1/app/call.py backend/tests/test_call_watchdog_force_exit_settlement.py
git commit -m "feat(call): settle force-exit by last-seen timestamp"
```

### Task 5: Flutter 通话页发送 WS 心跳

**Files:**
- Modify: `huanxi/lib/services/websocket_service.dart`
- Modify: `huanxi/lib/modules/call/call_room_page.dart`
- Test: `huanxi/test/services/websocket_service_call_heartbeat_test.dart`

- [ ] **Step 1: 写失败测试（发送报文格式）**

```dart
test('sendCallHeartbeat should send call_heartbeat payload', () async {
  // mock channel
  // expect sink.add(json) includes type=call_heartbeat and call_id
});
```

- [ ] **Step 2: 运行失败测试**

Run: `cd huanxi && dart test test/services/websocket_service_call_heartbeat_test.dart`
Expected: FAIL

- [ ] **Step 3: 最小实现 WS 发送方法**

```dart
// websocket_service.dart
Future<void> sendCallHeartbeat({required int callId}) async {
  if (_channel == null || !_authenticated) return;
  _channel!.sink.add(jsonEncode({'type': 'call_heartbeat', 'call_id': callId}));
}
```

- [ ] **Step 4: 在通话页启停心跳定时器**

```dart
// call_room_page.dart
// init/join success 后每 1s 调 sendCallHeartbeat(callId)
// leave/dispose 时 cancel timer
```

- [ ] **Step 5: 复跑测试**

Run: `cd huanxi && dart test test/services/websocket_service_call_heartbeat_test.dart`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add huanxi/lib/services/websocket_service.dart huanxi/lib/modules/call/call_room_page.dart huanxi/test/services/websocket_service_call_heartbeat_test.dart
git commit -m "feat(flutter): add ws call heartbeat in call room"
```

### Task 6: 关键链路回归测试与文档

**Files:**
- Modify: `backend/tests/test_call_watchdog_math.py`
- Create: `backend/tests/test_call_force_exit_concurrency.py`
- Modify: `docs/TODO.md`
- Create: `docs/superpowers/specs/2026-04-19-ws-force-exit-settlement-design.md`

- [ ] **Step 1: 新增并发回归测试（manual end vs watchdog）**

```python
@pytest.mark.asyncio
async def test_manual_end_race_watchdog_only_one_settlement(...):
    # 并发触发 /call/end 与 watchdog
    # 断言最终仅一次有效结算
```

- [ ] **Step 2: 运行后端用例集（仅通话相关）**

Run: `cd backend && pytest tests/test_call_* tests/test_websocket_* -q`
Expected: PASS

- [ ] **Step 3: 更新文档（配置项与降级说明）**

```markdown
# 说明新增配置
- call_presence_offline_detect_seconds
- call_presence_settle_grace_seconds
```

- [ ] **Step 4: 提交**

```bash
git add backend/tests docs/TODO.md docs/superpowers/specs/2026-04-19-ws-force-exit-settlement-design.md
git commit -m "test/docs: add force-exit settlement regression coverage"
```

### Task 7: 联调验收清单（手工）

**Files:**
- Create: `docs/superpowers/plans/2026-04-19-ws-force-exit-settlement-qa-checklist.md`

- [ ] **Step 1: 写验收脚本（时间点强杀）**

```text
场景A：9s强杀 -> 0费
场景B：10~60s强杀 -> 1分钟
场景C：59s/60s/61s强杀 -> 边界符合向上取整
场景D：双端同时强杀 -> 以最早last_seen结算
```

- [ ] **Step 2: 执行并记录结果**

Run: `手工执行 + 采集 call_record 与用户余额快照`
Expected: 全部符合预期

- [ ] **Step 3: 提交**

```bash
git add docs/superpowers/plans/2026-04-19-ws-force-exit-settlement-qa-checklist.md
git commit -m "docs(qa): add force-exit settlement checklist"
```

---

## Plan Self-Review

- Spec 覆盖：已覆盖纯 WS 心跳、强退判定、按强退时间结算、并发幂等、前后端联调。
- 占位检查：无 TBD/TODO 占位步骤，均给出文件与命令。
- 一致性检查：所有任务统一使用 `effective_ended_at` 作为强退结算时间。
