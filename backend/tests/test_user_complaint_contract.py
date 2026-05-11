import sys
from pathlib import Path

import pytest
from pydantic import ValidationError

BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO = BACKEND_ROOT.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.schemas.user_complaint import (  # noqa: E402
    ComplaintCreateIn,
    ComplaintHandleIn,
)


def _read(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def _all_migrations() -> str:
    return "\n".join(
        path.read_text(encoding="utf-8") for path in sorted((BACKEND_ROOT / "migrations/models").glob("*.py"))
    )


def test_complaint_schema_validates_content_and_status() -> None:
    item = ComplaintCreateIn(
        target_user_id=2,
        scene="chat",
        reason="骚扰辱骂",
        content="对方持续骚扰",
    )
    assert item.target_user_id == 2
    assert item.scene == "chat"

    with pytest.raises(ValidationError):
        ComplaintCreateIn(target_user_id=0, scene="chat", reason="其他", content="x")

    with pytest.raises(ValidationError):
        ComplaintCreateIn(target_user_id=2, scene="moment", reason="其他", content="x")

    with pytest.raises(ValidationError):
        ComplaintCreateIn(target_user_id=2, scene="chat", reason="其他", content="   ")

    with pytest.raises(ValidationError):
        ComplaintHandleIn(id=1, status="pending", handle_remark="处理中")


def test_complaint_model_routes_and_admin_contract_exist() -> None:
    model_text = _read("app/models/user_complaint.py")
    schema_text = _read("app/schemas/user_complaint.py")
    model_init_text = _read("app/models/__init__.py")
    app_init_text = _read("app/api/v1/app/__init__.py")
    v1_init_text = _read("app/api/v1/__init__.py")
    app_api_text = _read("app/api/v1/app/complaint.py")
    admin_api_text = _read("app/api/v1/complaint/complaint.py")

    assert "class UserComplaint" in model_text
    assert 'table = "user_complaint"' in model_text
    assert "complainant_id = fields.BigIntField" in model_text
    assert "target_user_id = fields.BigIntField" in model_text
    assert "handle_remark" in model_text
    assert "handled_by" in model_text
    assert "handled_at" in model_text
    assert "from .user_complaint import *" in model_init_text

    assert "class ComplaintCreateIn" in schema_text
    assert "class ComplaintHandleIn" in schema_text
    assert "class ComplaintListItem" in schema_text
    assert "target_complaint_count" in schema_text
    assert "target_pending_complaint_count" in schema_text
    assert "target_risk_flag" in schema_text

    assert "complaint_router" in app_init_text
    assert "complaint_router" in v1_init_text
    assert '@router.post("/complaint/create"' in app_api_text
    assert "不能投诉自己" in app_api_text
    assert '@router.get("/list"' in admin_api_text
    assert '@router.get("/detail"' in admin_api_text
    assert '@router.put("/handle"' in admin_api_text
    assert "target_complaint_count" in admin_api_text
    assert "target_pending_complaint_count" in admin_api_text
    assert "multiple_complaints" in admin_api_text
    assert "start_time" in admin_api_text
    assert "end_time" in admin_api_text
    assert 'order_by("-created_at", "-id")' in admin_api_text
    assert "handled_by" in admin_api_text


def test_complaint_migration_and_admin_web_exist() -> None:
    migration_text = _all_migrations()
    web_api_text = _read("web/src/api/index.js")
    web_view_text = _read("web/src/views/operation/complaint/index.vue")

    assert "CREATE TABLE `user_complaint`" in migration_text
    assert "/api/v1/app/complaint/create" in migration_text
    assert "/api/v1/complaint/list" in migration_text
    assert "/api/v1/complaint/detail" in migration_text
    assert "/api/v1/complaint/handle" in migration_text
    assert "'投诉管理'" in migration_text
    assert "'/operation/complaint'" in migration_text
    assert "role_menu" in migration_text
    assert "role_api" in migration_text

    assert "getComplaintList" in web_api_text
    assert "getComplaintDetail" in web_api_text
    assert "handleComplaint" in web_api_text
    assert "投诉管理" in web_view_text
    assert "累计被投诉次数" in web_view_text
    assert "待处理投诉次数" in web_view_text
    assert "多次被投诉" in web_view_text
    assert "处理投诉不会自动封禁用户" in web_view_text
    assert "查看用户" in web_view_text
    assert "提交时间" in web_view_text
    assert "pending" in web_view_text
    assert "processing" in web_view_text
    assert "resolved" in web_view_text
    assert "rejected" in web_view_text
