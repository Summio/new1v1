import json
from datetime import datetime
from pathlib import Path

import pytest

from app.core import init_app


REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_ROOT = REPO_ROOT / "backend"
HUANXI_ROOT = REPO_ROOT / "huanxi"

MODEL_FILE = BACKEND_ROOT / "app/models/app_user_common_phrase.py"
MODELS_INIT = BACKEND_ROOT / "app/models/__init__.py"
SERVICE_FILE = BACKEND_ROOT / "app/services/common_phrase_service.py"
APP_API_FILE = BACKEND_ROOT / "app/api/v1/app/certification.py"
APP_INIT_FILE = BACKEND_ROOT / "app/api/v1/app/__init__.py"
ADMIN_API_FILE = BACKEND_ROOT / "app/api/v1/app_users/app_users.py"
INIT_APP_FILE = BACKEND_ROOT / "app/core/init_app.py"
WEB_API_FILE = BACKEND_ROOT / "web/src/api/index.js"
WEB_REVIEW_PAGE = BACKEND_ROOT / "web/src/views/operation/common-phrase-review/index.vue"
MIGRATIONS_DIR = BACKEND_ROOT / "migrations/models"

CERTIFICATION_CENTER_PAGE = HUANXI_ROOT / "lib/modules/home/certification_center_page.dart"
API_ENDPOINTS = HUANXI_ROOT / "lib/core/constants/api_endpoints.dart"
ROUTER_FILE = HUANXI_ROOT / "lib/app/routes/app_router.dart"


def test_common_phrase_model_and_migration_contract() -> None:
    assert MODEL_FILE.exists()
    model_text = MODEL_FILE.read_text(encoding="utf-8")
    models_init = MODELS_INIT.read_text(encoding="utf-8")
    migrations_text = "\n".join(
        path.read_text(encoding="utf-8") for path in sorted(MIGRATIONS_DIR.glob("*common_phrase*.py"))
    )

    assert "class AppUserCommonPhrase" in model_text
    assert 'table = "app_user_common_phrase"' in model_text
    assert "unique_together" in model_text
    assert "user_id" in model_text
    assert "slot_index" in model_text
    assert "approved_content" in model_text
    assert "pending_content" in model_text
    assert "review_status" in model_text
    assert "review_remark" in model_text
    assert "from .app_user_common_phrase import *" in models_init
    assert "app_user_common_phrase" in migrations_text
    assert "slot_index" in migrations_text
    assert "approved_content" in migrations_text
    assert "pending_content" in migrations_text


def test_common_phrase_service_preserves_approved_content_until_review() -> None:
    from app.services.common_phrase_service import (
        apply_common_phrase_review,
        build_common_phrase_slots,
        validate_common_phrase_content,
    )

    assert validate_common_phrase_content(" 你好 ") == "你好"
    with pytest.raises(ValueError):
        validate_common_phrase_content("")
    with pytest.raises(ValueError):
        validate_common_phrase_content("一" * 51)

    slots = build_common_phrase_slots([])
    assert [slot["slot_index"] for slot in slots] == [1, 2, 3]
    assert all(slot["review_status"] == "none" for slot in slots)

    row = {
        "approved_content": "A",
        "pending_content": "B",
        "review_status": "pending",
        "review_remark": "",
    }
    rejected = apply_common_phrase_review(row, status="rejected", review_remark="不合规")
    assert rejected["approved_content"] == "A"
    assert rejected["pending_content"] == "B"
    assert rejected["review_status"] == "rejected"
    assert rejected["review_remark"] == "不合规"

    approved = apply_common_phrase_review(rejected, status="approved", review_remark="")
    assert approved["approved_content"] == "B"
    assert approved["pending_content"] == ""
    assert approved["review_status"] == "approved"
    assert approved["review_remark"] == ""


def test_common_phrase_slots_are_json_serializable() -> None:
    from app.services.common_phrase_service import build_common_phrase_slots

    submitted_at = datetime(2026, 5, 14, 13, 40, 51)
    reviewed_at = datetime(2026, 5, 14, 13, 41, 51)
    slots = build_common_phrase_slots(
        [
            {
                "id": 1,
                "user_id": 100019,
                "slot_index": 1,
                "approved_content": "你好",
                "pending_content": "很高兴认识你",
                "review_status": "pending",
                "review_remark": "",
                "submitted_at": submitted_at,
                "reviewed_at": reviewed_at,
                "reviewed_by": 1,
            }
        ]
    )

    json.dumps({"phrases": slots}, ensure_ascii=False)
    assert slots[0]["submitted_at"] == submitted_at.isoformat()
    assert slots[0]["reviewed_at"] == reviewed_at.isoformat()


def test_common_phrase_app_and_admin_api_contract() -> None:
    app_text = APP_API_FILE.read_text(encoding="utf-8")
    app_init = APP_INIT_FILE.read_text(encoding="utf-8")
    admin_text = ADMIN_API_FILE.read_text(encoding="utf-8")
    endpoints_text = API_ENDPOINTS.read_text(encoding="utf-8")

    assert '"/certification/common-phrases"' in app_text
    assert '"/certification/common-phrases/{slot_index}"' in app_text
    assert "仅真人认证用户可设置常用语" in app_text
    assert "AppUserCommonPhrase" in app_text
    assert "common_phrase_service" in app_text
    assert "certification_router" in app_init
    assert "certifiedCommonPhrases" in endpoints_text
    assert "app/certification/common-phrases" in endpoints_text

    assert '"/common-phrase-review/list"' in admin_text
    assert '"/common-phrase-review/get"' in admin_text
    assert '"/common-phrase-review/review"' in admin_text
    assert "AppUserCommonPhrase" in admin_text
    assert "pending_content" in admin_text
    assert "approved_content" in admin_text
    assert "review_remark" in admin_text


def test_common_phrase_admin_menu_seed_and_migration_contract() -> None:
    review_children = init_app.build_review_children(parent_id=200)
    summary = {(menu.name, menu.path, menu.component, menu.order) for menu in review_children}
    init_text = INIT_APP_FILE.read_text(encoding="utf-8")
    migrations_text = "\n".join(
        path.read_text(encoding="utf-8") for path in sorted(MIGRATIONS_DIR.glob("*common_phrase*.py"))
    )

    assert ("常用语审核", "common-phrase-review", "/operation/common-phrase-review", 6) in summary
    assert 'name="常用语审核"' in init_text
    assert 'path="common-phrase-review"' in init_text
    assert 'component="/operation/common-phrase-review"' in init_text
    assert "common-phrase-review" in migrations_text
    assert "order" in migrations_text
    assert "6" in migrations_text


def test_common_phrase_admin_frontend_contract() -> None:
    assert WEB_REVIEW_PAGE.exists()
    api_text = WEB_API_FILE.read_text(encoding="utf-8")
    view_text = WEB_REVIEW_PAGE.read_text(encoding="utf-8")

    assert "getCommonPhraseReviewList" in api_text
    assert "getCommonPhraseReviewById" in api_text
    assert "reviewCommonPhrase" in api_text
    assert "/app_user/common-phrase-review/list" in api_text
    assert "/app_user/common-phrase-review/get" in api_text
    assert "/app_user/common-phrase-review/review" in api_text

    assert "常用语审核" in view_text
    assert "res.rows || res.data || []" in view_text
    assert "total: res.total || 0" in view_text
    assert "待审核" in view_text
    assert "已通过内容" in view_text
    assert "待审核内容" in view_text
    assert "审核通过" in view_text
    assert "审核驳回" in view_text
    assert "reviewCommonPhrase" in view_text


def test_certification_center_split_pages_contract() -> None:
    text = CERTIFICATION_CENTER_PAGE.read_text(encoding="utf-8")
    router_text = ROUTER_FILE.read_text(encoding="utf-8")

    assert "CertificationHomePage" in text
    assert "CertificationApplyPage" in text
    assert "CertifiedCallPricePage" in text
    assert "CertifiedCommonPhrasesPage" in text
    assert "真人认证" in text
    assert "通话价格" in text
    assert "常用语" in text
    assert "已通过" in text
    assert "待审核" in text
    assert "已通过条数" in text
    assert "待审核条数" in text
    assert "常用语1" in text
    assert "常用语2" in text
    assert "常用语3" in text
    assert "50" in text
    assert "CertifiedCommonPhraseInfo" in text
    assert "certifiedCommonPhrases" in text

    assert "certificationApply" in router_text
    assert "certificationCallPrice" in router_text
    assert "certificationCommonPhrases" in router_text
