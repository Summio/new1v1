# 通知与弹窗纯拉取改造设计

最后更新：2026-05-17

## 背景

当前系统通知和在线弹窗同时使用数据库记录、进程内调度器和 WebSocket 推送。该模式在移动端网络切换、App 后台、服务重启、多 worker 部署时容易出现推送丢失、重复调度或进程内后台任务中断等问题。

本次改造目标是降低对“长时间运行进程内任务 + WebSocket 主动推送”的依赖。通知和弹窗改为 App 主动拉取为主；WebSocket 相关事件删除。搭讪批量发送暂不纳入本次改造。

## 目标

- 通知改为纯拉取。
- 删除系统通知未读数/红点能力。
- 保留通知列表、详情、单条已读/未读、全部已读能力。
- 弹窗改为纯拉取。
- 删除系统弹窗 WebSocket 推送能力。
- 从 FastAPI lifespan 移除通知/弹窗进程内长期调度器。
- 不改动搭讪业务。
- 不改动通话 watchdog。

## 非目标

- 本次不设计搭讪持久任务。
- 本次不设计外部 cron、Celery、RQ、Arq 等后台任务系统。
- 本次不删除通知和弹窗任务表。
- 本次不做数据库表结构变更。
- 本次不改变 IM 未读数能力。

## 通知设计

通知仍然由后台任务或系统业务写入 `system_notification`，并为目标用户写入 `system_notification_receipt`。Receipt 仍然表示该用户是否拥有这条通知，以及该条通知的 `read_at` 状态。

后端保留：

- `GET /api/v1/app/notifications`
- `GET /api/v1/app/notifications/{notification_id}`
- `POST /api/v1/app/notifications/{notification_id}/read`
- `POST /api/v1/app/notifications/{notification_id}/unread`
- `POST /api/v1/app/notifications/read-all`

后端删除或停用：

- `GET /api/v1/app/notifications/unread-count`
- `system_notification_unread_changed` WebSocket 事件
- 通知发布后批量推送未读数
- 详情自动标记已读后的未读数推送
- 单条已读/未读和全部已读后的未读数推送

App 删除系统通知未读数状态，不再请求 `notifications/unread-count`。底部“聊天”Tab 红点只显示 IM 未读数。消息页保留“系统通知”入口，但不显示系统通知未读数。通知列表和通知详情继续展示单条已读/未读状态。

## 弹窗设计

弹窗从“在线 WebSocket 推送”改为“App 主动拉取待展示弹窗”。后端不再依赖在线状态筛选，也不再调用 WebSocket 推送。App 在进入主 Shell、登录状态恢复、App 回到前台等时机主动拉取弹窗；展示后调用 ack。

后端保留：

- `POST /api/v1/app/popups/startup`
- `POST /api/v1/app/popups/{popup_id}/ack`

后端可以新增更清晰的接口：

- `POST /api/v1/app/popups/pending`

如果新增 `pending`，可复用当前 `startup` 的请求结构和响应结构。`startup` 可作为兼容入口继续存在。

待展示弹窗规则：

- 任务状态为 `running`。
- 当前用户符合目标范围。
- 当前弹窗实例对该用户未确认。
- 每次返回数量受现有上限控制。
- 用户确认后写入 `ack_at`，后续拉取不再返回。

App 删除 `system_popup_pending` WebSocket 事件处理。现有展示保护继续保留：

- 用户已登录。
- App 在前台。
- 当前不在通话相关页面。
- 当前没有系统弹窗正在展示。
- 同一弹窗在本轮生命周期内不重复处理。

## 调度器设计

从 FastAPI `lifespan` 移除：

- `run_system_notification_scheduler(stop_event)`
- `run_system_popup_scheduler(stop_event)`

调度器源码文件和服务函数可以保留，避免扩大改动范围。管理后台即时发布仍可由接口同步处理。定时和周期发布不再由 API 进程内长期任务自动执行。若后续需要定时/周期发布，应通过外部 cron 或独立 worker 重新设计。

## 兼容与风险

- 删除通知未读数接口后，App 不能再请求该接口。
- 删除 WebSocket 事件后，App 不能再监听 `system_notification_unread_changed` 和 `system_popup_pending`。
- 弹窗纯拉取后，原“仅在线触达”的语义会变为“符合条件用户拉取时可见”。这符合本次可靠性目标，但运营文案后续应同步调整。
- 定时/周期任务没有外部调度器时不会自动触发；后台页面后续应禁用或提示该能力需要外部调度。

## 验收标准

- 后端启动不再创建通知/弹窗 scheduler 长期任务。
- 后端通知服务不再调用通知 WebSocket 推送。
- 后端弹窗服务不再调用弹窗 WebSocket 推送。
- App 不再请求系统通知未读数接口。
- App 底部聊天红点只由 IM 未读数决定。
- App 不再处理通知/弹窗 WebSocket 事件。
- 通知列表、详情、单条已读/未读、全部已读仍可用。
- 弹窗可由 App 主动拉取展示并 ack。
- 后端相关测试通过。
- Flutter 相关测试通过，或明确记录无法运行的环境原因。
