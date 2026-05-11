from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent

MODEL_FILE = ROOT / "app/models/feedback.py"
SCHEMA_FILE = ROOT / "app/schemas/feedback.py"
APP_API_FILE = ROOT / "app/api/v1/app/feedback.py"
ADMIN_API_FILE = ROOT / "app/api/v1/feedback/feedback.py"
APP_INIT_FILE = ROOT / "app/api/v1/app/__init__.py"
V1_INIT_FILE = ROOT / "app/api/v1/__init__.py"
MODEL_INIT_FILE = ROOT / "app/models/__init__.py"
WEB_API_FILE = ROOT / "web/src/api/index.js"
WEB_VIEW_FILE = ROOT / "web/src/views/operation/feedback/index.vue"
MIGRATIONS_DIR = ROOT / "migrations/models"


def test_feedback_model_and_schema_are_registered() -> None:
    assert MODEL_FILE.exists()
    model_text = MODEL_FILE.read_text(encoding="utf-8")
    assert "class Feedback" in model_text
    assert 'table = "feedback"' in model_text
    assert "user_id = fields.BigIntField" in model_text
    assert 'content = fields.CharField(max_length=1000' in model_text

    schema_text = SCHEMA_FILE.read_text(encoding="utf-8")
    assert "class FeedbackCreateIn" in schema_text
    assert "min_length=1" in schema_text
    assert "max_length=1000" in schema_text
    assert "class FeedbackListItem" in schema_text

    init_text = MODEL_INIT_FILE.read_text(encoding="utf-8")
    assert "from .feedback import *" in init_text


def test_feedback_routers_are_registered() -> None:
    app_init_text = APP_INIT_FILE.read_text(encoding="utf-8")
    v1_init_text = V1_INIT_FILE.read_text(encoding="utf-8")
    app_api_text = APP_API_FILE.read_text(encoding="utf-8")
    admin_api_text = ADMIN_API_FILE.read_text(encoding="utf-8")

    assert "feedback_router" in app_init_text
    assert 'include_router(feedback_router, prefix="", dependencies=[Depends(DependAppAuth)])' in app_init_text
    assert "feedback_router" in v1_init_text
    assert 'include_router(feedback_router, prefix="/feedback", dependencies=[DependPermission])' in v1_init_text
    assert '/feedback/create' in app_api_text
    assert '提交意见反馈' in app_api_text
    assert '@router.get("/list"' in admin_api_text
    assert '@router.delete("/delete"' in admin_api_text
    assert '删除意见反馈' in admin_api_text


def test_feedback_migration_and_admin_web_exist() -> None:
    migration_text = "\n".join(path.read_text(encoding="utf-8") for path in sorted(MIGRATIONS_DIR.glob("*.py")))
    assert 'CREATE TABLE `feedback`' in migration_text
    assert '`content` VARCHAR(1000)' in migration_text
    assert '/api/v1/app/feedback/create' in migration_text
    assert '/api/v1/feedback/list' in migration_text
    assert '/api/v1/feedback/delete' in migration_text
    assert "'feedback'" in migration_text
    assert "'/operation/feedback'" in migration_text
    assert 'role_menu' in migration_text
    assert 'role_api' in migration_text
    assert '意见反馈' in migration_text

    assert WEB_API_FILE.exists()
    web_api_text = WEB_API_FILE.read_text(encoding="utf-8")
    assert 'getFeedbackList' in web_api_text
    assert 'deleteFeedback' in web_api_text

    assert WEB_VIEW_FILE.exists()
    web_view_text = WEB_VIEW_FILE.read_text(encoding="utf-8")
    assert '意见反馈管理' in web_view_text
    assert '确认删除' in web_view_text
    assert '提交时间' in web_view_text
