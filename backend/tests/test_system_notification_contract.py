from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_FILE = ROOT / "app/__init__.py"
MODEL_FILE = ROOT / "app/models/system_notification.py"
SCHEMA_FILE = ROOT / "app/schemas/system_notification.py"
SERVICE_FILE = ROOT / "app/services/system_notification_service.py"
APP_API_FILE = ROOT / "app/api/v1/app/notification.py"
ADMIN_API_FILE = ROOT / "app/api/v1/notification/notification.py"
APP_INIT_FILE = ROOT / "app/api/v1/app/__init__.py"
V1_INIT_FILE = ROOT / "app/api/v1/__init__.py"
MODEL_INIT_FILE = ROOT / "app/models/__init__.py"
WS_EVENTS_FILE = ROOT / "app/websocket/events.py"
INIT_APP_FILE = ROOT / "app/core/init_app.py"
WEB_API_FILE = ROOT / "web/src/api/index.js"
WEB_VIEW_FILE = ROOT / "web/src/views/operation/system-notification/index.vue"
WEB_QUERY_BAR_ITEM_FILE = ROOT / "web/src/components/query-bar/QueryBarItem.vue"
MIGRATIONS_DIR = ROOT / "migrations/models"


def test_system_notification_backend_files_and_models_exist() -> None:
    assert MODEL_FILE.exists()
    model_text = MODEL_FILE.read_text(encoding="utf-8")
    assert "class SystemNotificationTask" in model_text
    assert "class SystemNotification(" in model_text
    assert "class SystemNotificationReceipt" in model_text
    assert 'table = "system_notification_task"' in model_text
    assert 'table = "system_notification"' in model_text
    assert 'table = "system_notification_receipt"' in model_text
    assert "unique_together" in model_text
    assert "task_id" in model_text
    assert "scheduled_run_at" in model_text
    assert "biz_key" in model_text
    assert "read_at" in model_text
    assert "title = fields.CharField" not in model_text
    assert "summary = fields.CharField" not in model_text

    assert SCHEMA_FILE.exists()
    schema_text = SCHEMA_FILE.read_text(encoding="utf-8")
    assert "NotificationType" in schema_text
    assert "SystemNotificationTaskCreateIn" in schema_text
    assert "SystemNotificationUnreadOut" not in schema_text
    assert "SystemNotificationLatestOut" not in schema_text
    assert "title: str" not in schema_text
    assert "summary: str" not in schema_text

    assert SERVICE_FILE.exists()
    service_text = SERVICE_FILE.read_text(encoding="utf-8")
    assert "ensure_repeat_has_end_condition" in service_text
    assert "calculate_next_run_at" in service_text
    assert "estimate_target_count" in service_text
    assert "create_business_notification" in service_text
    assert "mark_notification_unread" in service_text
    assert "push_system_notification_unread_changed" not in service_text
    assert "_push_unread_changed" not in service_text
    assert '"title":' not in service_text
    assert '"summary":' not in service_text

    init_text = MODEL_INIT_FILE.read_text(encoding="utf-8")
    assert "from .system_notification import *" in init_text


def test_system_notification_routes_and_websocket_are_registered() -> None:
    assert APP_API_FILE.exists()
    app_api_text = APP_API_FILE.read_text(encoding="utf-8")
    assert '@router.get("/notifications"' in app_api_text
    assert '@router.get("/notifications/unread-count"' not in app_api_text
    assert '@router.get("/notifications/{notification_id}"' in app_api_text
    assert '@router.post("/notifications/{notification_id}/read"' in app_api_text
    assert '@router.post("/notifications/{notification_id}/unread"' in app_api_text
    assert '@router.post("/notifications/read-all"' in app_api_text
    assert "delete" not in app_api_text.lower()

    assert ADMIN_API_FILE.exists()
    admin_api_text = ADMIN_API_FILE.read_text(encoding="utf-8")
    assert '@router.get("/list"' in admin_api_text
    assert '@router.post("/estimate-target-count"' in admin_api_text
    assert '@router.post("/create"' in admin_api_text
    assert '@router.post("/pause"' in admin_api_text
    assert '@router.post("/resume"' in admin_api_text
    assert '@router.post("/cancel"' in admin_api_text
    assert "title__contains" not in admin_api_text
    assert "content__contains" in admin_api_text

    app_init_text = APP_INIT_FILE.read_text(encoding="utf-8")
    v1_init_text = V1_INIT_FILE.read_text(encoding="utf-8")
    assert "notification_router" in app_init_text
    assert 'include_router(notification_router, prefix="", dependencies=[Depends(DependAppAuth)])' in app_init_text
    assert "notification_router" in v1_init_text
    assert (
        'include_router(notification_router, prefix="/notification", dependencies=[DependPermission])' in v1_init_text
    )

    ws_text = WS_EVENTS_FILE.read_text(encoding="utf-8")
    assert "push_system_notification_unread_changed" not in ws_text
    assert "system_notification_unread_changed" not in ws_text


def test_system_notification_migration_and_admin_web_exist() -> None:
    migration_text = "\n".join(path.read_text(encoding="utf-8") for path in sorted(MIGRATIONS_DIR.glob("*.py")))
    assert "CREATE TABLE `system_notification_task`" in migration_text
    assert "CREATE TABLE `system_notification`" in migration_text
    assert "CREATE TABLE `system_notification_receipt`" in migration_text
    assert "system_notification_task_scheduled_run" in migration_text
    assert "system_notification_biz_key" in migration_text
    assert "DROP COLUMN `title`" in migration_text
    assert "DROP COLUMN `summary`" in migration_text
    assert "/api/v1/notification/estimate-target-count" in migration_text
    assert "/api/v1/notification/update" in migration_text
    assert "/api/v1/notification/publish" in migration_text
    assert "/api/v1/notification/pause" in migration_text
    assert "/api/v1/notification/resume" in migration_text
    assert "/api/v1/notification/cancel" in migration_text
    assert "/api/v1/notification/delete" in migration_text
    assert "系统通知" in migration_text

    init_app_text = INIT_APP_FILE.read_text(encoding="utf-8")
    assert "系统通知" in init_app_text
    assert "/operation/system-notification" in init_app_text
    assert "system-notification" in init_app_text

    assert WEB_API_FILE.exists()
    web_api_text = WEB_API_FILE.read_text(encoding="utf-8")
    assert "getSystemNotificationList" in web_api_text
    assert "estimateSystemNotificationTargetCount" in web_api_text
    assert "pauseSystemNotification" in web_api_text
    assert "resumeSystemNotification" in web_api_text

    assert WEB_VIEW_FILE.exists()
    web_view_text = WEB_VIEW_FILE.read_text(encoding="utf-8")
    assert "系统通知" in web_view_text
    assert "预计触达人数" in web_view_text
    assert "周期重复" in web_view_text
    assert "max_runs" in web_view_text
    assert "在线状态" in web_view_text
    assert "form.target_filters.is_online" in web_view_text
    assert "认证状态" not in web_view_text
    assert "form.target_filters.certification_status" not in web_view_text
    assert "账号状态" not in web_view_text
    assert "form.target_filters.status" not in web_view_text
    assert "#tableHeader" not in web_view_text
    assert "openEdit" in web_view_text
    assert "publishSystemNotification" in web_view_text
    assert "标题关键词" not in web_view_text
    assert "正文关键词" in web_view_text
    assert "form.title" not in web_view_text
    assert "form.summary" not in web_view_text
    assert "detail.title" not in web_view_text
    assert "detail.summary" not in web_view_text
    assert '<QueryBarItem label="类型" :label-width="45" :content-width="140">' in web_view_text
    assert '<QueryBarItem label="状态" :label-width="45" :content-width="140">' in web_view_text
    assert '<QueryBarItem label="发送模式" :label-width="70" :content-width="160">' in web_view_text


def test_system_notification_scheduler_is_not_started_in_api_lifespan() -> None:
    app_text = APP_FILE.read_text(encoding="utf-8")
    scheduler_text = (ROOT / "app/core/system_notification_scheduler.py").read_text(encoding="utf-8")

    assert "run_system_notification_scheduler" not in app_text
    assert "notification_task" not in app_text
    assert "publish_due_notifications" not in scheduler_text
    assert "materialize on pull" in scheduler_text


def test_notification_pull_materializes_due_tasks_without_push_or_scheduler() -> None:
    service_text = SERVICE_FILE.read_text(encoding="utf-8")
    app_text = APP_API_FILE.read_text(encoding="utf-8")
    events_text = WS_EVENTS_FILE.read_text(encoding="utf-8")
    init_text = APP_FILE.read_text(encoding="utf-8")

    assert "materialize_due_notifications_for_user" in service_text
    assert "materialize_due_notifications_for_user" in service_text.split("async def list_user_notifications", 1)[1]
    assert "run_system_notification_scheduler" not in init_text
    assert "system_notification_unread_changed" not in events_text
    assert "unread-count" not in app_text


def test_admin_notification_publish_activates_task_without_batch_send() -> None:
    api_text = ADMIN_API_FILE.read_text(encoding="utf-8")
    service_text = SERVICE_FILE.read_text(encoding="utf-8")

    publish_section = api_text.split("async def publish_notification", 1)[1].split("async def pause_notification", 1)[0]
    assert "activate_notification_task" in publish_section
    assert "publish_task_once" not in publish_section
    assert "publish_due_notifications" not in publish_section
    assert "async def materialize_due_notifications_for_user" in service_text


def test_admin_notification_actions_remain_available_for_lazy_pull_mode() -> None:
    api_text = ADMIN_API_FILE.read_text(encoding="utf-8")
    web_text = WEB_VIEW_FILE.read_text(encoding="utf-8")

    for fn in [
        "async def list_notification_tasks",
        "async def get_notification_task",
        "async def estimate_notification_target_count",
        "async def create_notification",
        "async def update_notification",
        "async def publish_notification",
        "async def pause_notification",
        "async def resume_notification",
        "async def cancel_notification",
        "async def delete_notification",
    ]:
        assert fn in api_text

    assert "task.status not in {\"draft\", \"scheduled\", \"paused\"}" in api_text
    assert "task.status != \"running\"" in api_text
    assert "task.send_mode != \"repeat\"" not in api_text
    assert "已产生用户记录" in api_text
    assert "api.createSystemNotification" in web_text
    assert "api.updateSystemNotification" in web_text
    assert "publishSystemNotification" in web_text
    assert "pauseSystemNotification" in web_text
    assert "resumeSystemNotification" in web_text
    assert "cancelSystemNotification" in web_text
    assert "deleteSystemNotification" in web_text
    assert "estimateSystemNotificationTargetCount" in web_text


def test_admin_query_bar_item_applies_content_width() -> None:
    assert WEB_QUERY_BAR_ITEM_FILE.exists()
    query_bar_item_text = WEB_QUERY_BAR_ITEM_FILE.read_text(encoding="utf-8")

    assert "contentWidth + 'px'" in query_bar_item_text
    assert "minWidth: contentWidth + 'px'" in query_bar_item_text
