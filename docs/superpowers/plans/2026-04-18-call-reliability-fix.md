# 通话系统可靠性修复计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复代码审查发现的 5 个问题（P0×1, P1×2, P2×2），确保通话结算的金额守恒、Pub/Sub 生命周期正确、日志可定位、测试覆盖完整。

**Architecture:** 4 个代码修改任务 + 1 个测试补充任务。全部在同一 `backend/` 目录内，无需改动前端。

**Tech Stack:** Python/FastAPI, Tortoise ORM, Redis, pytest/asyncio

---

## 修改文件清单

| 任务 | 文件 | 修改类型 |
|------|------|---------|
| Task 1 | `backend/app/api/v1/app/call.py` | 修改 |
| Task 2 | `backend/app/websocket/manager.py` | 修改 |
| Task 3 | `backend/app/core/call_watchdog.py` | 修改 |
| Task 4 | `backend/tests/test_watchdog_reliability.py` | 修改（追加） |

---

## Task 1: P0-3 charged_amount 下限校验

**Files:**
- Modify: `backend/app/api/v1/app/call.py:531-549`

**问题:** 第 534 行 `charged_amount = deducted_amount - refund_amount`，理论上 `refund_amount = max(0, deducted_amount - actual_fee)`，所以 `charged_amount` 永不为负。但若 `deducted_amount` 字段被外部污染或被错误写入，会导致负数进入 `total_fee`。

- [ ] **Step 1: 添加 charged_amount 下限校验**

在 `call.py:548`（`call_record.total_fee = charged_amount`）之前插入：

```python
            # P0-3 修复：金额守恒下限校验，防止 deducted_amount 异常时 total_fee 为负
            if charged_amount < 0:
                logger.error(
                    "call_end charged_amount negative: call_id={} deducted_amount={} actual_fee={}",
                    call_record.id,
                    deducted_amount,
                    actual_fee,
                )
                charged_amount = 0
```

完整上下文（第 531-549 行）修改后为：

```python
            actual_fee = due_minutes * int(call_record.call_price or 0)
            deducted_amount = int(call_record.deducted_amount or 0)
            refund_amount = max(0, deducted_amount - actual_fee)
            charged_amount = deducted_amount - refund_amount

            # P0-3 修复：金额守恒下限校验，防止 deducted_amount 异常时 total_fee 为负
            if charged_amount < 0:
                logger.error(
                    "call_end charged_amount negative: call_id={} deducted_amount={} actual_fee={}",
                    call_record.id,
                    deducted_amount,
                    actual_fee,
                )
                charged_amount = 0

            call_record.deducted_minutes = due_minutes
            call_record.total_fee = charged_amount
```

- [ ] **Step 2: 验证代码修改正确**

确认：
- `charged_amount` 在赋值给 `total_fee` 前有下限为 0 的校验
- 异常时记录包含 `call_id/deducted_amount/actual_fee` 三个定位字段

- [ ] **Step 3: 提交**

```bash
git add backend/app/api/v1/app/call.py
git commit -m "fix(call): P0-3 charged_amount 下限校验，防止负数进入 total_fee"
```

---

## Task 2: P1-4 Pub/Sub 生命周期状态管理修复

**Files:**
- Modify: `backend/app/websocket/manager.py:267-280`

**问题 2a:** 第 279 行 `global _pubsub_task` 缺失，`_pubsub_task = None` 写到了局部变量而非全局变量，导致 `stop_pubsub` 后全局 `_pubsub_task` 未被清理。

**问题 2b:** `self._pubsub_running` 在 `stop_pubsub` 后未被重置为 `False`。

- [ ] **Step 1: 修复 stop_pubsub 全局变量赋值**

将 `backend/app/websocket/manager.py:267-280` 的 `stop_pubsub` 方法替换为：

```python
    async def stop_pubsub(self) -> None:
        """停止 Pub/Sub 监听（进程退出时调用）。"""
        global _pubsub_started, _pubsub_task

        self._pubsub_running = False
        if self._pubsub_task:
            self._pubsub_task.cancel()
            try:
                await self._pubsub_task
            except asyncio.CancelledError:
                pass
            self._pubsub_task = None
        global _pubsub_task
        _pubsub_task = None
        _pubsub_started = False
```

注：添加了 `global _pubsub_task` 声明，并将 `_pubsub_started = False` 放在 `global` 声明之后（写法更清晰）。

- [ ] **Step 2: 验证代码修改**

确认 `global _pubsub_task` 在 `_pubsub_task = None` 之前被声明。

- [ ] **Step 3: 提交**

```bash
git add backend/app/websocket/manager.py
git commit -m "fix(websocket): P1-4 修复 stop_pubsub 全局变量赋值和 _pubsub_running 状态"
```

---

## Task 3: P2-1 balance_insufficient 日志补充 caller_id/callee_id

**Files:**
- Modify: `backend/app/core/call_watchdog.py:300-304` 和 `319-323`

**问题:** watchdog 关闭余额不足通话时，日志只包含 `call_id` 和 `duration`，缺少 `caller_id`/`callee_id` 定位字段。

- [ ] **Step 1: 补充第一处日志（第 300-304 行）**

在 `call_watchdog.py` 中，找到：

```python
                logger.warning(
                    "watchdog closed call_id={} (balance insufficient) duration={}s",
                    r["id"],
                    duration,
                )
```

替换为：

```python
                logger.warning(
                    "watchdog closed call_id={} caller_id={} callee_id={} (balance insufficient) duration={}s",
                    r["id"],
                    r["caller_id"],
                    r["callee_id"],
                    duration,
                )
```

- [ ] **Step 2: 补充第二处日志（第 319-323 行）**

找到：

```python
                logger.warning(
                    "watchdog closed call_id={} (conditional update failed) duration={}s",
                    r["id"],
                    duration,
                )
```

替换为：

```python
                logger.warning(
                    "watchdog closed call_id={} caller_id={} callee_id={} (conditional update failed) duration={}s",
                    r["id"],
                    r["caller_id"],
                    r["callee_id"],
                    duration,
                )
```

- [ ] **Step 3: 验证代码修改**

确认两处日志都包含 `call_id/caller_id/callee_id/duration` 四个字段。

- [ ] **Step 4: 提交**

```bash
git add backend/app/core/call_watchdog.py
git commit -m "fix(watchdog): P2-1 balance_insufficient 日志补充 caller_id/callee_id"
```

---

## Task 4: P2-2 测试补充 - push 失败降级和 PubSub 状态机

**Files:**
- Modify: `backend/tests/test_watchdog_reliability.py`（追加到文件末尾）

**现状:** `test_watchdog_reliability.py` 已覆盖：leader 续期成功/失败/NOSCRIPT、pending 误推送回归、leader 循环无异常。缺少：push 失败降级、PubSub 启停状态机。

- [ ] **Step 1: 追加 push 失败降级测试**

在 `test_watchdog_reliability.py` 末尾追加：

```python
# ===== P2-2: push 失败降级测试 =====


@pytest.mark.asyncio
async def test_push_failure_threshold_tracks_consecutive_failures():
    """连续推送失败应触发阈值告警"""
    from app.websocket.manager import ConnectionManager

    manager = ConnectionManager()

    # 模拟 Redis 推送持续失败
    mock_redis = AsyncMock()
    mock_redis.sismember = AsyncMock(return_value=True)
    mock_redis.publish = AsyncMock(side_effect=Exception("Redis unavailable"))

    with patch("app.websocket.manager.get_redis", return_value=mock_redis):
        with patch("app.websocket.manager.logger") as mock_logger:
            # 连续失败 2 次：未达阈值（_PUSH_FAIL_THRESHOLD=3）
            await manager.push_to_user(user_id=100, event="call_ended", data={}, critical=True)
            await manager.push_to_user(user_id=100, event="call_ended", data={}, critical=True)

            # 连续失败 3 次：触发阈值
            await manager.push_to_user(user_id=100, event="call_ended", data={}, critical=True)

            threshold_logs = [
                c for c in mock_logger.warning.call_args_list
                if "threshold exceeded" in str(c)
            ]
            assert len(threshold_logs) >= 1
            assert mock_logger.warning.called


@pytest.mark.asyncio
async def test_push_failure_threshold_resets_on_success():
    """推送成功后应重置失败计数器"""
    from app.websocket.manager import ConnectionManager

    manager = ConnectionManager()
    manager._push_failures[100] = 2  # 已有 2 次失败

    mock_redis = AsyncMock()
    mock_redis.sismember = AsyncMock(return_value=True)
    mock_redis.publish = AsyncMock(return_value=1)

    with patch("app.websocket.manager.get_redis", return_value=mock_redis):
        await manager.push_to_user(user_id=100, event="call_ended", data={})

    # 成功后计数器应被清除
    assert 100 not in manager._push_failures


# ===== P2-2: PubSub 启停状态机测试 =====


@pytest.mark.asyncio
async def test_stop_pubsub_resets_pubsub_running_flag():
    """stop_pubsub 应将 _pubsub_running 重置为 False"""
    from app.websocket import manager as manager_module
    from app.websocket.manager import ConnectionManager

    manager = ConnectionManager()
    manager_module._pubsub_started = True
    manager._pubsub_running = True
    task = asyncio.create_task(asyncio.sleep(0))
    manager._pubsub_task = task

    await manager.stop_pubsub()

    assert manager._pubsub_running is False
    assert manager_module._pubsub_started is False


@pytest.mark.asyncio
async def test_start_pubsub_idempotent_when_already_started():
    """重复调用 start_pubsub 不应启动多个监听"""
    from app.websocket import manager as manager_module
    from app.websocket.manager import ConnectionManager

    manager = ConnectionManager()
    fake_task = MagicMock()

    def _fake_create_task(coro):
        coro.close()
        return fake_task

    with patch("app.websocket.manager.asyncio.create_task", side_effect=_fake_create_task):
        await manager.start_pubsub()
        await manager.start_pubsub()  # 重复调用
        await manager.start_pubsub()  # 再重复调用

    # create_task 只应被调用 1 次
    # （后续调用因 _pubsub_started=True 而提前返回）


# ===== P1-4: global 变量赋值验证 =====


@pytest.mark.asyncio
async def test_stop_pubsub_clears_global_pubsub_task():
    """stop_pubsub 应清理全局 _pubsub_task 变量"""
    from app.websocket import manager as manager_module
    from app.websocket.manager import ConnectionManager

    manager = ConnectionManager()
    manager_module._pubsub_started = True
    manager._pubsub_running = True
    task = asyncio.create_task(asyncio.sleep(0))
    manager._pubsub_task = task
    manager_module._pubsub_task = task

    await manager.stop_pubsub()

    # 全局 _pubsub_task 应为 None
    assert manager_module._pubsub_task is None
    assert manager_module._pubsub_started is False
```

- [ ] **Step 2: 运行新增测试验证通过**

```bash
cd D:/1v1/new1v1/backend && python -m pytest tests/test_watchdog_reliability.py -v -k "push_failure or stop_pubsub or start_pubsub" --tb=short
```

预期：全部 PASS

- [ ] **Step 3: 运行完整测试套件确保无回归**

```bash
cd D:/1v1/new1v1/backend && python -m pytest tests/test_watchdog_reliability.py tests/test_websocket_manager.py tests/test_call_watchdog_math.py -q --tb=short
```

预期：全部 PASS

- [ ] **Step 4: 提交**

```bash
git add backend/tests/test_watchdog_reliability.py
git commit -m "test: P2-2 补充 push 失败降级和 PubSub 状态机测试"
```

---

## Task 5: ruff 检查

所有任务完成后执行。

- [ ] **Step 1: ruff 检查修改的文件**

```bash
cd D:/1v1/new1v1/backend && python -m ruff check app/api/v1/app/call.py app/websocket/manager.py app/core/call_watchdog.py tests/test_watchdog_reliability.py
```

预期：无 ERROR（WARNING 可接受）

---

## 汇总

| Task | 修改文件 | 问题编号 |
|------|---------|---------|
| 1 | `call.py:534` | P0-3 charged_amount 下限校验 |
| 2 | `manager.py:267-280` | P1-4 Pub/Sub 生命周期修复 |
| 3 | `call_watchdog.py:300-323` | P2-1 日志补充 caller_id/callee_id |
| 4 | `test_watchdog_reliability.py` | P2-2 补充测试覆盖 |
| 5 | - | ruff 检查验收 |

共 4 个代码/测试文件修改，1 个检查步骤。按顺序执行即可。
