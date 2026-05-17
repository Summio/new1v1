from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP_FILE = ROOT / "app/__init__.py"
MODEL_FILE = ROOT / "app/models/system_popup.py"
SCHEMA_FILE = ROOT / "app/schemas/system_popup.py"
SERVICE_FILE = ROOT / "app/services/system_popup_service.py"
SCHEDULER_FILE = ROOT / "app/core/system_popup_scheduler.py"
ADMIN_API_FILE = ROOT / "app/api/v1/popup/popup.py"
APP_API_FILE = ROOT / "app/api/v1/app/popup.py"
APP_INIT_FILE = ROOT / "app/api/v1/app/__init__.py"
V1_INIT_FILE = ROOT / "app/api/v1/__init__.py"
MODEL_INIT_FILE = ROOT / "app/models/__init__.py"
WS_EVENTS_FILE = ROOT / "app/websocket/events.py"
INIT_APP_FILE = ROOT / "app/core/init_app.py"
WEB_API_FILE = ROOT / "web/src/api/index.js"
WEB_VIEW_FILE = ROOT / "web/src/views/operation/popup/index.vue"
FLUTTER_ENDPOINTS_FILE = ROOT.parent / "huanxi/lib/core/constants/api_endpoints.dart"
FLUTTER_SERVICE_FILE = ROOT.parent / "huanxi/lib/services/system_popup_service.dart"
FLUTTER_MAIN_SHELL_FILE = ROOT.parent / "huanxi/lib/modules/home/main_shell.dart"
MIGRATIONS_DIR = ROOT / "migrations/models"


def test_system_popup_backend_contract_files_exist() -> None:
    assert MODEL_FILE.exists()
    model_text = MODEL_FILE.read_text(encoding="utf-8")
    assert "class SystemPopupTask" in model_text
    assert "class SystemPopup(" in model_text
    assert "class SystemPopupReceipt" in model_text
    assert 'table = "system_popup_task"' in model_text
    assert 'table = "system_popup"' in model_text
    assert 'table = "system_popup_receipt"' in model_text
    assert "pushed_at" in model_text
    assert "ack_at" in model_text
    assert "read_at" not in model_text

    assert SCHEMA_FILE.exists()
    schema_text = SCHEMA_FILE.read_text(encoding="utf-8")
    assert "SystemPopupTaskCreateIn" in schema_text
    assert "SystemPopupAckOut" in schema_text
    assert "SystemPopupStartupIn" in schema_text
    assert "APP_START" in schema_text
    assert "is_online" not in schema_text

    assert SERVICE_FILE.exists()
    service_text = SERVICE_FILE.read_text(encoding="utf-8")
    assert "publish_popup_task_once" in service_text
    assert "fetch_startup_popups_for_user" in service_text
    assert "fetch_pending_popups_for_user" in service_text
    assert "build_startup_popup_run_key" in service_text
    assert "ack_user_popup" in service_text
    assert "estimate_online_target_count" not in service_text
    assert "filter_online_user_ids" not in service_text
    assert "push_system_popup" not in service_text

    assert SCHEDULER_FILE.exists()
    scheduler_text = SCHEDULER_FILE.read_text(encoding="utf-8")
    assert "publish_due_popups" not in scheduler_text
    assert "materialize on pull" in scheduler_text

    model_init_text = MODEL_INIT_FILE.read_text(encoding="utf-8")
    assert "from .system_popup import *" in model_init_text


def test_system_popup_routes_menu_websocket_and_no_pending_api() -> None:
    assert ADMIN_API_FILE.exists()
    admin_text = ADMIN_API_FILE.read_text(encoding="utf-8")
    for expected in [
        '@router.get("/list"',
        '@router.get("/get"',
        '@router.post("/estimate-target-count"',
        '@router.post("/create"',
        '@router.post("/update"',
        '@router.post("/publish"',
        '@router.post("/pause"',
        '@router.post("/resume"',
        '@router.post("/cancel"',
        '@router.delete("/delete"',
    ]:
        assert expected in admin_text

    assert APP_API_FILE.exists()
    app_text = APP_API_FILE.read_text(encoding="utf-8")
    assert '@router.post("/popups/startup"' in app_text
    assert '@router.get("/popups/pending"' in app_text
    assert '@router.post("/popups/{popup_id}/ack"' in app_text

    app_init_text = APP_INIT_FILE.read_text(encoding="utf-8")
    v1_init_text = V1_INIT_FILE.read_text(encoding="utf-8")
    assert "popup_router" in app_init_text
    assert "popup_router" in v1_init_text
    assert 'prefix="/popup"' in v1_init_text

    ws_text = WS_EVENTS_FILE.read_text(encoding="utf-8")
    assert "push_system_popup_pending" not in ws_text
    assert "system_popup_pending" not in ws_text

    init_app_text = INIT_APP_FILE.read_text(encoding="utf-8")
    assert "弹窗提示" in init_app_text
    assert "popup" in init_app_text
    assert "/operation/popup" in init_app_text

    migration_text = "\n".join(path.read_text(encoding="utf-8") for path in sorted(MIGRATIONS_DIR.glob("*.py")))
    assert "CREATE TABLE `system_popup_task`" in migration_text
    assert "CREATE TABLE `system_popup`" in migration_text
    assert "CREATE TABLE `system_popup_receipt`" in migration_text
    assert "/api/v1/popup/list" in migration_text
    assert "/api/v1/app/popups/startup" in migration_text
    assert "/api/v1/app/popups/{popup_id}/ack" in migration_text


def test_system_popup_admin_and_flutter_contract() -> None:
    assert WEB_API_FILE.exists()
    web_api_text = WEB_API_FILE.read_text(encoding="utf-8")
    for expected in [
        "getSystemPopupList",
        "getSystemPopupDetail",
        "estimateSystemPopupTargetCount",
        "createSystemPopup",
        "updateSystemPopup",
        "publishSystemPopup",
        "pauseSystemPopup",
        "resumeSystemPopup",
        "cancelSystemPopup",
        "deleteSystemPopup",
    ]:
        assert expected in web_api_text

    assert WEB_VIEW_FILE.exists()
    web_view_text = WEB_VIEW_FILE.read_text(encoding="utf-8")
    assert "弹窗提示" in web_view_text
    assert "预计可拉取人数" in web_view_text
    assert "已拉取人数" in web_view_text
    assert "已确认人数" in web_view_text
    assert "下次可拉取时间" in web_view_text
    assert "已生成期数" in web_view_text
    assert "App启动时" in web_view_text
    assert "form.target_filters.is_online" not in web_view_text

    assert FLUTTER_ENDPOINTS_FILE.exists()
    endpoints_text = FLUTTER_ENDPOINTS_FILE.read_text(encoding="utf-8")
    assert "systemPopupStartup" in endpoints_text
    assert "systemPopupPending" in endpoints_text
    assert "systemPopupAckBase" in endpoints_text

    assert FLUTTER_SERVICE_FILE.exists()
    service_text = FLUTTER_SERVICE_FILE.read_text(encoding="utf-8")
    assert "class SystemPopupItem" in service_text
    assert "fetchStartupPopups" in service_text
    assert "fetchPendingPopups" in service_text
    assert "ackPopup" in service_text

    main_shell_text = FLUTTER_MAIN_SHELL_FILE.read_text(encoding="utf-8")
    assert "_fetchStartupSystemPopups" in main_shell_text
    assert "_fetchPendingSystemPopups" in main_shell_text
    assert "AppRoutes.callRoom" in main_shell_text
    assert "AppRoutes.callIncoming" in main_shell_text
    assert "AppRoutes.callOutgoing" in main_shell_text


def test_system_popup_scheduler_is_not_started_in_api_lifespan() -> None:
    app_text = APP_FILE.read_text(encoding="utf-8")

    assert "run_system_popup_scheduler" not in app_text
    assert "popup_task" not in app_text


def test_popup_pull_materializes_due_tasks_without_push_or_scheduler() -> None:
    service_text = SERVICE_FILE.read_text(encoding="utf-8")
    ws_text = WS_EVENTS_FILE.read_text(encoding="utf-8")
    app_text = APP_FILE.read_text(encoding="utf-8")

    assert "materialize_due_popups_for_user" in service_text
    assert "materialize_due_popups_for_user" in service_text.split("async def fetch_pending_popups_for_user", 1)[1]
    assert "materialize_startup_popups_for_user" in service_text
    assert "system_popup_pending" not in ws_text
    assert "run_system_popup_scheduler" not in app_text


def test_admin_popup_publish_activates_task_without_push_or_batch_send() -> None:
    api_text = ADMIN_API_FILE.read_text(encoding="utf-8")
    service_text = SERVICE_FILE.read_text(encoding="utf-8")

    publish_section = api_text.split("async def publish_popup", 1)[1].split("async def pause_popup", 1)[0]
    assert "activate_popup_task" in publish_section
    assert "publish_popup_task_once" not in publish_section
    assert "publish_due_popups" not in publish_section
    assert "async def materialize_due_popups_for_user" in service_text


def test_admin_popup_actions_remain_available_for_lazy_pull_mode() -> None:
    api_text = ADMIN_API_FILE.read_text(encoding="utf-8")
    web_text = WEB_VIEW_FILE.read_text(encoding="utf-8")

    for fn in [
        "async def list_popup_tasks",
        "async def get_popup_task",
        "async def estimate_popup_target_count",
        "async def create_popup",
        "async def update_popup",
        "async def publish_popup",
        "async def pause_popup",
        "async def resume_popup",
        "async def cancel_popup",
        "async def delete_popup",
    ]:
        assert fn in api_text

    assert "createSystemPopup" in web_text
    assert "updateSystemPopup" in web_text
    assert "publishSystemPopup" in web_text
    assert "pauseSystemPopup" in web_text
    assert "resumeSystemPopup" in web_text
    assert "cancelSystemPopup" in web_text
    assert "deleteSystemPopup" in web_text
    assert "estimateSystemPopupTargetCount" in web_text
