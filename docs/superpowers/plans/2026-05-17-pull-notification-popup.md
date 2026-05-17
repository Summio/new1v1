# 通知与弹窗纯拉取改造 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将系统通知和弹窗改为 App 主动拉取为主，删除通知未读数、通知/弹窗 WebSocket 推送，以及通知/弹窗 API 进程内长期调度器。

**Architecture:** 通知保留用户 receipt 和单条已读状态，但删除未读汇总链路。弹窗改为 pending/startup 拉取并 ack，不再按在线用户 WebSocket 推送。FastAPI lifespan 不再创建通知和弹窗 scheduler。

**Tech Stack:** FastAPI、Tortoise ORM、pytest、Flutter、Riverpod、Dio、flutter_test。

---

### Task 1: 后端通知去 WebSocket 和未读数

**Files:**
- Modify: `backend/app/services/system_notification_service.py`
- Modify: `backend/app/api/v1/app/notification.py`
- Modify: `backend/app/websocket/events.py`
- Test: `backend/tests/test_system_notification_service.py`
- Test: `backend/tests/test_system_notification_contract.py`

- [ ] **Step 1: 更新后端通知合同测试**

覆盖行为：

- App 通知未读数接口不再存在。
- `publish_task_once()` 不再调用 `_push_unread_changed_for_users()`。
- `get_user_notification_detail()` 标记已读但不推送 WebSocket。
- `mark_notification_read()`、`mark_notification_unread()`、`mark_all_notifications_read()` 只更新 `read_at`。

建议命令：

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_system_notification_contract.py tests/test_system_notification_service.py
```

预期先失败，失败点应指向仍存在 unread-count 或仍调用推送。

- [ ] **Step 2: 修改后端通知实现**

删除或停用 `get_unread_count()` 路由。服务层移除 `_push_unread_changed_for_users()` 和 `_push_unread_changed()` 的调用。保留列表、详情、已读/未读、全部已读。

- [ ] **Step 3: 运行通知相关测试**

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_system_notification_contract.py tests/test_system_notification_service.py
```

预期通过。

### Task 2: 后端弹窗改纯拉取

**Files:**
- Modify: `backend/app/services/system_popup_service.py`
- Modify: `backend/app/api/v1/app/popup.py`
- Modify: `backend/app/websocket/events.py`
- Test: `backend/tests/test_system_popup_service.py`
- Test: `backend/tests/test_system_popup_contract.py`

- [ ] **Step 1: 更新后端弹窗合同测试**

覆盖行为：

- 发布弹窗不再调用 `push_system_popup`。
- 发布弹窗不再只筛在线用户。
- App 可通过 startup/pending 拉取符合目标且未 ack 的弹窗。
- ack 后不再返回。
- `system_popup_pending` WebSocket 事件不再作为合同要求。

建议命令：

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_system_popup_contract.py tests/test_system_popup_service.py
```

预期先失败，失败点应指向在线筛选或 WebSocket 推送仍存在。

- [ ] **Step 2: 修改后端弹窗实现**

将弹窗发布改为落库，不推 WebSocket。拉取接口返回用户符合目标、未 ack 的弹窗。可以新增 `/app/popups/pending`，并保留 `/app/popups/startup` 兼容。

- [ ] **Step 3: 运行弹窗相关测试**

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_system_popup_contract.py tests/test_system_popup_service.py
```

预期通过。

### Task 3: 后端移除 lifespan 调度器

**Files:**
- Modify: `backend/app/__init__.py`
- Test: `backend/tests/test_backend_performance_contracts.py`
- Test: `backend/tests/test_system_popup_contract.py`
- Test: `backend/tests/test_system_notification_contract.py`

- [ ] **Step 1: 更新合同测试**

增加或调整断言，确认 `backend/app/__init__.py` 不再 import 或 create_task 通知/弹窗 scheduler。

- [ ] **Step 2: 修改 lifespan**

移除 `run_system_notification_scheduler` 和 `run_system_popup_scheduler` 的 import、`asyncio.create_task()` 和 shutdown await。保留 call watchdog 和 auditlog cleanup。

- [ ] **Step 3: 运行后端合同测试**

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_backend_performance_contracts.py tests/test_system_popup_contract.py tests/test_system_notification_contract.py
```

预期通过。

### Task 4: Flutter 删除通知未读数链路

**Files:**
- Modify: `huanxi/lib/services/system_notification_service.dart`
- Modify: `huanxi/lib/app/providers/system_notification_provider.dart`
- Modify: `huanxi/lib/modules/home/main_shell.dart`
- Modify: `huanxi/lib/modules/home/messages_page.dart`
- Modify: `huanxi/lib/core/constants/api_endpoints.dart`
- Test: `huanxi/test/modules/home/system_notifications_contract_test.dart`
- Test: `huanxi/test/modules/home/main_shell_contract_test.dart`

- [ ] **Step 1: 更新 Flutter 合同测试**

覆盖行为：

- 不再引用 `systemNotificationUnreadCount` endpoint。
- MainShell 不再处理 `system_notification_unread_changed`。
- 底部聊天红点只使用 IM 未读。
- 系统通知入口不显示系统通知未读数。
- 通知列表和详情已读状态仍保留。

建议命令：

```bash
cd D:/1v1/new1v1/huanxi
flutter test test/modules/home/system_notifications_contract_test.dart test/modules/home/main_shell_contract_test.dart
```

预期先失败。

- [ ] **Step 2: 修改 Flutter 通知实现**

删除未读汇总模型、服务方法、Provider 状态和 MainShell 中的刷新/监听。保留通知列表 Provider、详情加载、单条已读/未读和全部已读。

- [ ] **Step 3: 运行 Flutter 通知测试**

```bash
cd D:/1v1/new1v1/huanxi
flutter test test/modules/home/system_notifications_contract_test.dart test/modules/home/main_shell_contract_test.dart
```

预期通过。

### Task 5: Flutter 删除弹窗 WebSocket 监听

**Files:**
- Modify: `huanxi/lib/modules/home/main_shell.dart`
- Modify: `huanxi/lib/services/system_popup_service.dart`
- Modify: `huanxi/lib/core/constants/api_endpoints.dart`
- Test: `huanxi/test/modules/home/main_shell_contract_test.dart`

- [ ] **Step 1: 更新 Flutter 弹窗合同测试**

覆盖行为：

- MainShell 不再处理 `system_popup_pending` WebSocket 事件。
- MainShell 仍会在初始化和回前台主动拉取弹窗。
- ack 仍调用 App 弹窗确认接口。

- [ ] **Step 2: 修改 Flutter 弹窗实现**

删除 `_handleSystemPopupPending` 和 WebSocket switch case。保留 `_fetchStartupSystemPopups()` 或重命名为 pending 拉取。

- [ ] **Step 3: 运行 Flutter Shell 测试**

```bash
cd D:/1v1/new1v1/huanxi
flutter test test/modules/home/main_shell_contract_test.dart
```

预期通过。

### Task 6: 集成验证

**Files:**
- Read/Verify only unless发现回归

- [ ] **Step 1: 搜索残留引用**

```bash
cd D:/1v1/new1v1
rg -n "system_notification_unread_changed|system_popup_pending|notifications/unread-count|run_system_notification_scheduler|run_system_popup_scheduler" backend huanxi
```

预期只允许在历史设计/计划文档或保留的 scheduler 源文件中出现；运行入口和 App 业务代码不得继续引用。

- [ ] **Step 2: 运行后端相关测试**

```bash
cd D:/1v1/new1v1/backend
pytest -q tests/test_system_notification_contract.py tests/test_system_notification_service.py tests/test_system_popup_contract.py tests/test_system_popup_service.py tests/test_backend_performance_contracts.py
```

预期通过。

- [ ] **Step 3: 运行 Flutter 相关测试**

```bash
cd D:/1v1/new1v1/huanxi
flutter test test/modules/home/system_notifications_contract_test.dart test/modules/home/main_shell_contract_test.dart
```

预期通过。

- [ ] **Step 4: 静态检查**

```bash
cd D:/1v1/new1v1/backend
ruff check ./app
```

```bash
cd D:/1v1/new1v1/huanxi
flutter analyze
```

预期通过；如果环境缺工具，记录原因。
