from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
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

    assert SCHEMA_FILE.exists()
    schema_text = SCHEMA_FILE.read_text(encoding="utf-8")
    assert "NotificationType" in schema_text
    assert "SystemNotificationTaskCreateIn" in schema_text
    assert "SystemNotificationUnreadOut" in schema_text
    assert "SystemNotificationLatestOut" in schema_text

    assert SERVICE_FILE.exists()
    service_text = SERVICE_FILE.read_text(encoding="utf-8")
    assert "ensure_repeat_has_end_condition" in service_text
    assert "calculate_next_run_at" in service_text
    assert "estimate_target_count" in service_text
    assert "create_business_notification" in service_text
    assert "mark_notification_unread" in service_text

    init_text = MODEL_INIT_FILE.read_text(encoding="utf-8")
    assert "from .system_notification import *" in init_text


def test_system_notification_routes_and_websocket_are_registered() -> None:
    assert APP_API_FILE.exists()
    app_api_text = APP_API_FILE.read_text(encoding="utf-8")
    assert '@router.get("/notifications"' in app_api_text
    assert '@router.get("/notifications/unread-count"' in app_api_text
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

    app_init_text = APP_INIT_FILE.read_text(encoding="utf-8")
    v1_init_text = V1_INIT_FILE.read_text(encoding="utf-8")
    assert "notification_router" in app_init_text
    assert 'include_router(notification_router, prefix="", dependencies=[Depends(DependAppAuth)])' in app_init_text
    assert "notification_router" in v1_init_text
    assert (
        'include_router(notification_router, prefix="/notification", dependencies=[DependPermission])' in v1_init_text
    )

    ws_text = WS_EVENTS_FILE.read_text(encoding="utf-8")
    assert "push_system_notification_unread_changed" in ws_text
    assert "system_notification_unread_changed" in ws_text


def test_system_notification_migration_and_admin_web_exist() -> None:
    migration_text = "\n".join(path.read_text(encoding="utf-8") for path in sorted(MIGRATIONS_DIR.glob("*.py")))
    assert "CREATE TABLE `system_notification_task`" in migration_text
    assert "CREATE TABLE `system_notification`" in migration_text
    assert "CREATE TABLE `system_notification_receipt`" in migration_text
    assert "system_notification_task_scheduled_run" in migration_text
    assert "system_notification_biz_key" in migration_text
    assert "/api/v1/app/notifications/unread-count" in migration_text
    assert "/api/v1/notification/estimate-target-count" in migration_text
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
