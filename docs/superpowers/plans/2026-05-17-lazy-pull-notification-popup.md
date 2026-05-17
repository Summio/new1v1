# 通知与弹窗懒拉取调度 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不使用通知/弹窗 WebSocket 主动推送、不使用 FastAPI 进程内长期调度器、不使用外部短任务的前提下，保住通知和弹窗的立即发送、一次性定时、周期重复，以及弹窗 App 启动时能力。

**Architecture:** 后台任务表仍作为运营配置源，App 每次 HTTP 拉取时由后端按当前用户、当前时间和任务规则实时计算生效任务，并按需懒创建通知/弹窗实例与用户 receipt。通知保留列表、详情、单条已读/未读、全部已读；弹窗通过 startup/pending 拉取和 ack 闭环；WebSocket 不参与通知/弹窗链路。

**Tech Stack:** FastAPI、Tortoise ORM、pytest、Flutter、Riverpod、Dio、flutter_test、Vue3 管理后台。

---

## Scope

本计划是在 `docs/superpowers/plans/2026-05-17-pull-notification-popup.md` 已完成“删除通知/弹窗 WebSocket 和进程内 scheduler”的基础上继续演进。核心变化是：定时和周期不再提示依赖外部调度，而是改为 HTTP 拉取时懒结算。

本计划不处理搭讪，不改通话 WebSocket，不恢复系统通知未读数/红点，不引入 cron、Celery、RQ、Arq、APScheduler 或常驻 worker。

## File Structure

- `backend/app/services/system_notification_service.py`
  - 增加通知任务拉取时生效计算、周期 occurrence 计算、按需创建 `SystemNotification` 和 `SystemNotificationReceipt`。
  - `list_user_notifications()` 在分页查询前先为当前用户懒物化应可见通知。
  - `get_user_notification_detail()`、已读/未读接口继续基于真实 `notification_id` 工作。

- `backend/app/services/system_popup_service.py`
  - 增加弹窗任务拉取时生效计算、周期 occurrence 计算、按需创建 `SystemPopup` 和 `SystemPopupReceipt`。
  - `fetch_startup_popups_for_user()` 只处理 `send_mode = app_start`。
  - `fetch_pending_popups_for_user()` 处理 `send_mode in immediate, once, repeat`。
  - `ack_user_popup()` 继续基于真实 `popup_id` 工作。

- `backend/app/api/v1/notification/notification.py`
  - 后台“发布”动作只激活任务，不再要求立即批量发送。
  - 删除、暂停、恢复语义按懒拉取模型调整。

- `backend/app/api/v1/popup/popup.py`
  - 后台“发布”动作只激活任务。
  - App 启动时弹窗继续作为 `send_mode = app_start` 保持兼容。

- `backend/app/api/v1/app/notification.py`
  - 保持 App 通知接口路径不变。
  - 列表拉取触发懒物化。

- `backend/app/api/v1/app/popup.py`
  - 保持 `startup`、`pending`、`ack` 路径不变。
  - 拉取触发懒物化。

- `backend/tests/test_system_notification_service.py`
  - 增加通知立即、一次定时、周期重复的拉取时生效测试。

- `backend/tests/test_system_popup_service.py`
  - 增加弹窗立即、一次定时、周期重复、App 启动时的拉取时生效测试。

- `backend/tests/test_system_notification_contract.py`
  - 增加通知不依赖 scheduler / WebSocket / 外部 job 语义的合同断言。

- `backend/tests/test_system_popup_contract.py`
  - 增加弹窗不依赖 scheduler / WebSocket / 外部 job 语义的合同断言。

- `backend/web/src/views/operation/system-notification/index.vue`
  - 调整后台文案：发送表示“进入可拉取状态”，不是服务端主动推送。

- `backend/web/src/views/operation/popup/index.vue`
  - 调整后台文案：弹窗到点后由 App startup/pending 拉取。

- `huanxi/lib/modules/home/main_shell.dart`
  - 增加或确认弹窗 pending HTTP 轮询，App 前台时运行，后台停止。
  - 不处理通知/弹窗 WebSocket 事件。

- `huanxi/lib/services/system_popup_service.dart`
  - 保持 startup/pending/ack HTTP 方法。

- `huanxi/test/modules/home/main_shell_contract_test.dart`
  - 增加弹窗轮询和不监听 WebSocket 的合同测试。

---

### Task 1: 锁定懒拉取合同

**Files:**
- Modify: `backend/tests/test_system_notification_contract.py`
- Modify: `backend/tests/test_system_popup_contract.py`
- Modify: `huanxi/test/modules/home/main_shell_contract_test.dart`

- [ ] **Step 1: 增加后端通知合同断言**

在 `backend/tests/test_system_notification_contract.py` 增加文本合同，要求通知拉取链路必须包含懒物化入口，并且不得重新引入 scheduler/WebSocket 推送。

建议测试内容：

```python
def test_notification_pull_materializes_due_tasks_without_push_or_scheduler():
    service_text = (BACKEND_ROOT / "app/services/system_notification_service.py").read_text(encoding="utf-8")
    app_text = (BACKEND_ROOT / "app/api/v1/app/notification.py").read_text(encoding="utf-8")
    events_text = (BACKEND_ROOT / "app/websocket/events.py").read_text(encoding="utf-8")
    init_text = (BACKEND_ROOT / "app/__init__.py").read_text(encoding="utf-8")

    assert "materialize_due_notifications_for_user" in service_text
    assert "materialize_due_notifications_for_user" in service_text.split("async def list_user_notifications", 1)[1]
    assert "run_system_notification_scheduler" not in init_text
    assert "system_notification_unread_changed" not in events_text
    assert "unread-count" not in app_text
```

- [ ] **Step 2: 增加后端弹窗合同断言**

在 `backend/tests/test_system_popup_contract.py` 增加文本合同，要求 startup/pending 走拉取时物化，并且不得恢复弹窗 WebSocket 事件。

建议测试内容：

```python
def test_popup_pull_materializes_due_tasks_without_push_or_scheduler():
    service_text = (BACKEND_ROOT / "app/services/system_popup_service.py").read_text(encoding="utf-8")
    events_text = (BACKEND_ROOT / "app/websocket/events.py").read_text(encoding="utf-8")
    init_text = (BACKEND_ROOT / "app/__init__.py").read_text(encoding="utf-8")

    assert "materialize_due_popups_for_user" in service_text
    assert "materialize_due_popups_for_user" in service_text.split("async def fetch_pending_popups_for_user", 1)[1]
    assert "materialize_startup_popups_for_user" in service_text
    assert "system_popup_pending" not in events_text
    assert "run_system_popup_scheduler" not in init_text
```

- [ ] **Step 3: 增加 Flutter 合同断言**

在 `huanxi/test/modules/home/main_shell_contract_test.dart` 增加断言：

```dart
test('main shell polls system popups over http without websocket popup events', () {
  final source = File('lib/modules/home/main_shell.dart').readAsStringSync();

  expect(source, contains('fetchPendingPopups'));
  expect(source, isNot(contains('system_popup_pending')));
  expect(source, isNot(contains('_handleSystemPopupPending')));
});
```

- [ ] **Step 4: 运行合同测试确认失败点正确**

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_system_notification_contract.py tests/test_system_popup_contract.py

cd D:/1v1/new1v1/huanxi
flutter test test/modules/home/main_shell_contract_test.dart
```

预期：如果懒物化函数尚未实现，相关新增断言失败；不应出现语法错误或无关测试崩溃。

### Task 2: 实现通知 occurrence 计算和懒物化

**Files:**
- Modify: `backend/app/services/system_notification_service.py`
- Test: `backend/tests/test_system_notification_service.py`

- [ ] **Step 1: 增加通知服务单元测试**

在 `backend/tests/test_system_notification_service.py` 覆盖以下行为：

```python
async def test_list_user_notifications_materializes_immediate_task_for_target_user():
    # 创建 running + immediate + target all 任务。
    # 调用 list_user_notifications(user_id=..., page=1, page_size=20)。
    # 断言返回 1 条通知，receipt 被创建，第二次拉取不重复创建 SystemNotification。
```

```python
async def test_list_user_notifications_hides_once_task_before_publish_at():
    # 创建 running + once + publish_at 在未来的任务。
    # 调用 list_user_notifications。
    # 断言返回空列表，SystemNotification 没有被创建。
```

```python
async def test_list_user_notifications_materializes_once_task_after_publish_at():
    # 创建 running + once + publish_at 在过去的任务。
    # 调用 list_user_notifications。
    # 断言返回该通知，scheduled_run_at 等于 publish_at 对应批次。
```

```python
async def test_list_user_notifications_materializes_recent_repeat_occurrences():
    # 创建 running + repeat daily + repeat_time + start_at 在三天前的任务。
    # 调用 list_user_notifications。
    # 断言返回最近周期实例，每个实例 run_key 不同，重复拉取不重复创建。
```

```python
async def test_list_user_notifications_does_not_materialize_for_non_target_user():
    # 创建 running + immediate + user_ids 任务，但当前 user_id 不在目标里。
    # 调用 list_user_notifications。
    # 断言没有通知，也没有 receipt。
```

- [ ] **Step 2: 新增 occurrence 数据结构**

在 `backend/app/services/system_notification_service.py` 增加轻量内部类，避免在多个函数间传散乱元组：

```python
@dataclass(frozen=True)
class NotificationOccurrence:
    scheduled_run_at: datetime
    run_key: str
    published_at: datetime
```

需要新增 import：

```python
from dataclasses import dataclass
```

- [ ] **Step 3: 实现通知 due occurrence 计算**

在 `backend/app/services/system_notification_service.py` 增加：

```python
def _notification_due_occurrences(
    task: SystemNotificationTask,
    *,
    now: datetime,
    max_backfill: int = 30,
) -> list[NotificationOccurrence]:
    ...
```

实现规则：

- `status != "running"` 返回空。
- `send_mode == "immediate"`：`scheduled_run_at = task.created_at or now`，只生成一次。
- `send_mode == "once"`：`publish_at <= now` 才生成一次。
- `send_mode == "repeat"`：按 `repeat_type/repeat_time/repeat_weekday/repeat_month_day/start_at/end_at/max_runs` 计算截至 `now` 已到期的最近 `max_backfill` 个周期。
- 如果 `end_at` 存在且 occurrence 晚于 `end_at`，不返回。
- `run_key` 使用已有 `build_run_key(task_id=int(task.id), scheduled_run_at=scheduled_run_at)`。

- [ ] **Step 4: 实现用户目标判断复用**

在通知服务中新增：

```python
async def is_user_targeted_by_notification_task(
    *,
    user_id: int,
    target_mode: str,
    target_user_ids: list[int] | None,
    target_filters: dict[str, Any] | None,
) -> bool:
    ...
```

规则与弹窗已有 `is_user_targeted_by_popup_task()` 保持一致：

- `all`：返回 `True`。
- `user_ids`：判断 `user_id` 是否在列表内。
- `filter`：复用 `_target_query("filter", None, filters)` 并加 `id=user_id`。

- [ ] **Step 5: 实现通知实例 get-or-create**

增加：

```python
async def _get_or_create_notification_for_occurrence(
    *,
    task: SystemNotificationTask,
    occurrence: NotificationOccurrence,
) -> SystemNotification:
    ...
```

行为：

- 先按 `run_key` 查询 `SystemNotification`。
- 存在则返回。
- 不存在则创建 `SystemNotification`，字段来自 task：
  - `task_id`
  - `content`
  - `type`
  - `source = "admin"`
  - `publish_at = occurrence.scheduled_run_at`
  - `published_at = occurrence.published_at`
  - `scheduled_run_at = occurrence.scheduled_run_at`
  - `run_key = occurrence.run_key`
- 并发唯一键冲突时重新查询 `run_key` 返回，避免重复。

- [ ] **Step 6: 实现通知用户懒物化入口**

增加：

```python
async def materialize_due_notifications_for_user(
    *,
    user_id: int,
    now: datetime | None = None,
    max_backfill: int = 30,
) -> int:
    ...
```

行为：

- 查询 `SystemNotificationTask`：
  - `status = "running"`
  - `send_mode in ["immediate", "once", "repeat"]`
- 对每个任务先判断目标用户是否命中。
- 计算 due occurrences。
- 对每个 occurrence 创建或复用 `SystemNotification`。
- 为当前用户创建或复用 `SystemNotificationReceipt(notification_id, user_id)`。
- 返回本次新建 receipt 数，便于测试。

- [ ] **Step 7: 接入通知列表**

在 `list_user_notifications()` 开头调用：

```python
await materialize_due_notifications_for_user(user_id=user_id)
```

之后保留现有基于 receipt 的分页查询和 `_dump_user_notification()`。

- [ ] **Step 8: 运行通知服务测试**

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_system_notification_service.py tests/test_system_notification_contract.py
```

预期通过。

### Task 3: 调整通知后台发布语义

**Files:**
- Modify: `backend/app/services/system_notification_service.py`
- Modify: `backend/app/api/v1/notification/notification.py`
- Test: `backend/tests/test_system_notification_contract.py`

- [ ] **Step 1: 增加后台发布合同测试**

在 `backend/tests/test_system_notification_contract.py` 增加断言：

```python
def test_admin_notification_publish_activates_task_without_batch_send():
    api_text = (BACKEND_ROOT / "app/api/v1/notification/notification.py").read_text(encoding="utf-8")
    service_text = (BACKEND_ROOT / "app/services/system_notification_service.py").read_text(encoding="utf-8")

    publish_section = api_text.split("async def publish_notification", 1)[1].split("async def pause_notification", 1)[0]
    assert "activate_notification_task" in publish_section
    assert "publish_task_once" not in publish_section
    assert "publish_due_notifications" not in publish_section
    assert "async def materialize_due_notifications_for_user" in service_text
```

- [ ] **Step 2: 修改 `activate_notification_task()`**

在 `backend/app/services/system_notification_service.py` 中确认激活行为：

- 所有 `send_mode` 激活后进入 `status = "running"`。
- `next_run_at` 可以继续作为管理后台展示字段，但不作为后台调度触发依据。
- 不调用 `publish_task_once()`。
- `immediate` 的 `next_run_at` 可置为当前时间或 `None`，不影响 App 拉取。

- [ ] **Step 3: 修改后台发布接口**

在 `backend/app/api/v1/notification/notification.py` 中确认 `publish_notification()`：

```python
await activate_notification_task(task)
return Success(data=await _dump_task(task), msg="发布成功，用户下次拉取时可见")
```

不要调用任何批量发送、调度或 WebSocket 方法。

- [ ] **Step 4: 运行通知合同测试**

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_system_notification_contract.py tests/test_system_notification_service.py
```

预期通过。

### Task 4: 实现弹窗 occurrence 计算和懒物化

**Files:**
- Modify: `backend/app/services/system_popup_service.py`
- Test: `backend/tests/test_system_popup_service.py`

- [ ] **Step 1: 增加弹窗服务单元测试**

在 `backend/tests/test_system_popup_service.py` 覆盖以下行为：

```python
async def test_pending_popups_materializes_immediate_popup_for_target_user():
    # running + immediate + target all。
    # fetch_pending_popups_for_user 返回 1 条弹窗。
    # 第二次拉取不重复创建 SystemPopup。
```

```python
async def test_pending_popups_hides_once_popup_before_publish_at():
    # running + once + publish_at 在未来。
    # fetch_pending_popups_for_user 返回空。
```

```python
async def test_pending_popups_materializes_once_popup_after_publish_at():
    # running + once + publish_at 在过去。
    # fetch_pending_popups_for_user 返回 1 条。
```

```python
async def test_pending_popups_materializes_current_repeat_occurrence_only():
    # running + repeat daily。
    # fetch_pending_popups_for_user 只返回当前最近一期，不补历史多期。
```

```python
async def test_startup_popups_materializes_app_start_task():
    # running + app_start。
    # fetch_startup_popups_for_user 返回启动弹窗。
```

```python
async def test_popup_ack_hides_materialized_popup():
    # 拉取弹窗得到 popup id。
    # ack_user_popup 后再次 fetch_pending_popups_for_user 返回空。
```

- [ ] **Step 2: 新增弹窗 occurrence 数据结构**

在 `backend/app/services/system_popup_service.py` 增加：

```python
@dataclass(frozen=True)
class PopupOccurrence:
    scheduled_run_at: datetime
    run_key: str
    published_at: datetime
```

需要新增 import：

```python
from dataclasses import dataclass
```

- [ ] **Step 3: 实现弹窗 due occurrence 计算**

增加：

```python
def _popup_due_occurrences(
    task: SystemPopupTask,
    *,
    now: datetime,
    mode: str,
) -> list[PopupOccurrence]:
    ...
```

规则：

- `status != "running"` 返回空。
- `mode = "startup"` 时只处理 `send_mode = "app_start"`。
- `mode = "pending"` 时只处理 `send_mode in ["immediate", "once", "repeat"]`。
- `immediate` 和 `app_start`：只生成一次。
- `once`：`publish_at <= now` 才生成一次。
- `repeat`：只返回当前最近已到期的一期，不补历史多期。
- 如果 `end_at` 存在且当前时间超过 `end_at`，不返回。
- `run_key` 使用 `build_popup_run_key(task_id=int(task.id), scheduled_run_at=scheduled_run_at)`；不再把 `launch_id` 放进 run key，避免每次启动制造新弹窗实例。

- [ ] **Step 4: 实现弹窗实例 get-or-create**

增加：

```python
async def _get_or_create_popup_for_occurrence(
    *,
    task: SystemPopupTask,
    occurrence: PopupOccurrence,
) -> SystemPopup:
    ...
```

行为：

- 先按 `run_key` 查询 `SystemPopup`。
- 存在则返回。
- 不存在则创建 `SystemPopup`，字段来自 task：
  - `task_id`
  - `title`
  - `content`
  - `type`
  - `publish_at = occurrence.scheduled_run_at`
  - `published_at = occurrence.published_at`
  - `scheduled_run_at = occurrence.scheduled_run_at`
  - `run_key = occurrence.run_key`
- 并发唯一键冲突时重新查询。

- [ ] **Step 5: 实现弹窗用户懒物化入口**

增加：

```python
async def materialize_due_popups_for_user(
    *,
    user_id: int,
    mode: str,
    now: datetime | None = None,
) -> int:
    ...
```

行为：

- `mode` 只允许 `"startup"` 或 `"pending"`。
- 查询 `SystemPopupTask(status="running")`。
- 根据 `mode` 过滤 `send_mode`。
- 判断当前用户是否命中目标。
- 计算 due occurrence。
- 创建或复用 `SystemPopup`。
- 创建或复用 `SystemPopupReceipt(popup_id, user_id, pushed_at=now)`。
- 如果 receipt 已有 `ack_at`，不计入待展示。
- 返回本次新建或复用待展示 receipt 数，便于测试。

同时增加兼容包装：

```python
async def materialize_startup_popups_for_user(
    *,
    user_id: int,
    now: datetime | None = None,
) -> int:
    return await materialize_due_popups_for_user(user_id=user_id, mode="startup", now=now)
```

- [ ] **Step 6: 接入 startup/pending 拉取**

在 `fetch_startup_popups_for_user()` 开头调用：

```python
await materialize_startup_popups_for_user(user_id=user_id)
```

在 `fetch_pending_popups_for_user()` 开头调用：

```python
await materialize_due_popups_for_user(user_id=user_id, mode="pending")
```

之后继续使用现有基于 `SystemPopup` + `SystemPopupReceipt` 的过滤和 `_dump_app_popup()` 返回。

- [ ] **Step 7: 确认 ack 语义**

`ack_user_popup()` 继续用 `popup_id` 查 receipt：

- 找到当前用户 receipt 后写 `ack_at`。
- 找不到则返回 `False`。
- 不需要虚拟 id，Flutter 端保持现有整数 `popupId`。

- [ ] **Step 8: 运行弹窗服务测试**

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_system_popup_service.py tests/test_system_popup_contract.py
```

预期通过。

### Task 5: 调整弹窗后台发布语义

**Files:**
- Modify: `backend/app/services/system_popup_service.py`
- Modify: `backend/app/api/v1/popup/popup.py`
- Test: `backend/tests/test_system_popup_contract.py`

- [ ] **Step 1: 增加后台发布合同测试**

在 `backend/tests/test_system_popup_contract.py` 增加：

```python
def test_admin_popup_publish_activates_task_without_push_or_batch_send():
    api_text = (BACKEND_ROOT / "app/api/v1/popup/popup.py").read_text(encoding="utf-8")
    service_text = (BACKEND_ROOT / "app/services/system_popup_service.py").read_text(encoding="utf-8")

    publish_section = api_text.split("async def publish_popup", 1)[1].split("async def pause_popup", 1)[0]
    assert "activate_popup_task" in publish_section
    assert "publish_popup_task_once" not in publish_section
    assert "publish_due_popups" not in publish_section
    assert "async def materialize_due_popups_for_user" in service_text
```

- [ ] **Step 2: 修改 `activate_popup_task()`**

在 `backend/app/services/system_popup_service.py` 中确认：

- 所有弹窗任务发布后进入 `status = "running"`。
- `send_mode = "app_start"` 表示只在 `POST /api/v1/app/popups/startup` 中被拉取。
- `send_mode in ["immediate", "once", "repeat"]` 表示在 `GET /api/v1/app/popups/pending` 中被拉取。
- 不调用 WebSocket，不批量创建在线用户 receipt。

- [ ] **Step 3: 修改后台发布接口文案**

在 `backend/app/api/v1/popup/popup.py` 中确认 `publish_popup()` 返回：

```python
return Success(data=await _dump_task(task), msg="发布成功，App 下次拉取时可见")
```

- [ ] **Step 4: 运行弹窗合同测试**

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_system_popup_contract.py tests/test_system_popup_service.py
```

预期通过。

### Task 6: 管理后台文案和状态展示

**Files:**
- Modify: `backend/web/src/views/operation/system-notification/index.vue`
- Modify: `backend/web/src/views/operation/popup/index.vue`
- Test: `backend/tests/test_system_notification_contract.py`
- Test: `backend/tests/test_system_popup_contract.py`

- [ ] **Step 1: 增加后台文案合同**

在后端合同测试中增加文本断言，避免后台继续暗示“主动推送”：

```python
def test_admin_notification_page_explains_pull_visibility():
    text = (REPO_ROOT / "backend/web/src/views/operation/system-notification/index.vue").read_text(encoding="utf-8")
    assert "用户下次拉取" in text or "下次进入通知列表" in text
    assert "WebSocket" not in text
```

```python
def test_admin_popup_page_explains_pull_visibility():
    text = (REPO_ROOT / "backend/web/src/views/operation/popup/index.vue").read_text(encoding="utf-8")
    assert "App下次拉取" in text or "App 下次拉取" in text
    assert "WebSocket" not in text
```

- [ ] **Step 2: 修改通知后台文案**

在 `backend/web/src/views/operation/system-notification/index.vue` 的发送方式附近增加简短提示：

```text
发布后不会主动推送；立即发送表示用户下次拉取通知列表时可见，定时/周期表示到点后可被拉取。
```

- [ ] **Step 3: 修改弹窗后台文案**

在 `backend/web/src/views/operation/popup/index.vue` 的发送方式附近增加简短提示：

```text
发布后不会主动推送；弹窗由 App 启动或前台轮询接口拉取，ack 后不再重复展示同一期。
```

- [ ] **Step 4: 运行合同测试**

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_system_notification_contract.py tests/test_system_popup_contract.py
```

预期通过。

### Task 7: Flutter 弹窗 HTTP 轮询

**Files:**
- Modify: `huanxi/lib/modules/home/main_shell.dart`
- Modify: `huanxi/lib/services/system_popup_service.dart`
- Test: `huanxi/test/modules/home/main_shell_contract_test.dart`

- [ ] **Step 1: 增加 Flutter 轮询合同测试**

在 `huanxi/test/modules/home/main_shell_contract_test.dart` 增加断言：

```dart
test('main shell starts and stops popup polling with lifecycle', () {
  final source = File('lib/modules/home/main_shell.dart').readAsStringSync();

  expect(source, contains('Timer.periodic'));
  expect(source, contains('fetchPendingPopups'));
  expect(source, contains('AppLifecycleState.resumed'));
  expect(source, contains('AppLifecycleState.paused'));
  expect(source, contains('cancel'));
});
```

- [ ] **Step 2: 确认 popup service 暴露 pending 拉取**

在 `huanxi/lib/services/system_popup_service.dart` 确认存在：

```dart
Future<List<SystemPopupItem>> fetchPendingPopups()
```

该方法调用：

```text
GET /api/v1/app/popups/pending
```

并解析 `data.items`。

- [ ] **Step 3: 在 MainShell 增加前台轮询**

在 `huanxi/lib/modules/home/main_shell.dart`：

- 增加 `Timer? _systemPopupPollingTimer;`。
- `initState()` 登录态就绪后调用启动弹窗拉取，并启动 pending 轮询。
- `didChangeAppLifecycleState(AppLifecycleState.resumed)` 立即拉一次 pending 并启动轮询。
- `didChangeAppLifecycleState(AppLifecycleState.paused)` / `inactive` 停止轮询。
- `dispose()` 停止轮询。

建议间隔：

```dart
static const Duration _systemPopupPollingInterval = Duration(seconds: 60);
```

不要低于 15 秒。

- [ ] **Step 4: 保持展示保护**

轮询回调复用现有弹窗展示保护：

- 用户已登录。
- App 在前台。
- 当前不在通话页面。
- 当前没有系统弹窗正在展示。
- 同一 popup id 在本轮生命周期内不重复处理。

- [ ] **Step 5: 运行 Flutter 合同测试**

```bash
cd D:/1v1/new1v1/huanxi
flutter test test/modules/home/main_shell_contract_test.dart
```

预期通过。

### Task 8: 集成验证

**Files:**
- Verify only unless发现回归

- [ ] **Step 1: 搜索不允许的链路残留**

```bash
cd D:/1v1/new1v1
rg -n "system_notification_unread_changed|system_popup_pending|notifications/unread-count|run_system_notification_scheduler|run_system_popup_scheduler|publish_due_notifications\\(|publish_due_popups\\(" backend/app huanxi/lib backend/tests huanxi/test -S
```

预期：

- App 和 API 运行入口不得引用通知/弹窗 WebSocket 事件。
- `backend/app/__init__.py` 不得引用通知/弹窗 scheduler。
- `publish_due_notifications()` / `publish_due_popups()` 如果保留源码，只能作为未使用兼容函数，不得在 lifespan 或后台发布 API 中调用。

- [ ] **Step 2: 运行后端通知/弹窗测试**

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_system_notification_contract.py tests/test_system_notification_service.py tests/test_system_popup_contract.py tests/test_system_popup_service.py tests/test_backend_performance_contracts.py
```

预期通过。

- [ ] **Step 3: 运行后端 WebSocket 回归**

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_websocket_manager.py tests/test_websocket_router_heartbeat.py tests/test_websocket_router_call_heartbeat.py tests/test_call_presence.py
```

预期通过。该验证确保通知/弹窗改造没有误伤通话和在线状态 WebSocket。

- [ ] **Step 4: 运行后端 lint**

```bash
cd D:/1v1/new1v1/backend
ruff check app tests/test_system_notification_contract.py tests/test_system_notification_service.py tests/test_system_popup_contract.py tests/test_system_popup_service.py
```

预期输出：

```text
All checks passed!
```

- [ ] **Step 5: 运行 Flutter 相关测试**

```bash
cd D:/1v1/new1v1/huanxi
flutter test test/modules/home/system_notifications_contract_test.dart test/modules/home/main_shell_contract_test.dart
```

预期通过。

- [ ] **Step 6: 运行 Flutter analyze**

```bash
cd D:/1v1/new1v1/huanxi
flutter analyze
```

预期：

```text
No issues found!
```

## Acceptance Criteria

- 通知立即发送：后台发布后任务进入 `running`，目标用户下次 `GET /api/v1/app/notifications` 可见。
- 通知一次性定时：`publish_at` 到达前不可见，到达后目标用户拉取可见。
- 通知周期重复：目标用户拉取时按周期生成最近有限数量的通知实例，每期有独立 `run_key` 和已读状态。
- 弹窗立即发送：后台发布后目标用户下次 `GET /api/v1/app/popups/pending` 可见。
- 弹窗一次性定时：`publish_at` 到达前不可见，到达后 pending 拉取可见。
- 弹窗周期重复：pending 拉取时只展示当前最近一期，不补历史弹窗堆积。
- 弹窗 App 启动时：`send_mode = app_start` 只通过 `POST /api/v1/app/popups/startup` 返回。
- 弹窗 ack 后，同一 popup id 对该用户不再返回。
- 后端没有通知/弹窗 WebSocket 主动推送。
- 后端没有通知/弹窗 FastAPI lifespan 长跑调度器。
- 没有外部短任务、cron、worker 依赖。
- 系统通知未读数/红点不恢复。
- 搭讪业务不修改。

## Operational Notes

- “立即发送”的产品语义是“立即进入可拉取状态”，不是在线用户秒级强推。
- “一次性定时”的产品语义是“到达指定时间后可被拉取”。
- “周期重复”的产品语义是“每个周期到达后，用户拉取时生成该周期实例”。
- 通知可以补最近 `max_backfill = 30` 个周期实例；弹窗不补历史，只展示当前最近一期。
- 运营统计口径应以“实际拉取/实际展示/实际 ack/实际已读”为准，不能再把“发布任务”理解为“已触达全部目标用户”。
