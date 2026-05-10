from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent

APP_USER_API = ROOT / "app/api/v1/app/user.py"
ADMIN_APP_USER_API = ROOT / "app/api/v1/app_users/app_users.py"
APP_MODELS_INIT = ROOT / "app/models/__init__.py"
PROFILE_REVIEW_MODEL = ROOT / "app/models/app_user_profile_review.py"
WEB_API = ROOT / "web/src/api/index.js"
WEB_REVIEW_VIEW = ROOT / "web/src/views/operation/profile-review/index.vue"
WEB_APP_USER_VIEW = ROOT / "web/src/views/operation/app-user/index.vue"
INIT_APP = ROOT / "app/core/init_app.py"
AUTH_PROVIDER = REPO / "huanxi/lib/app/providers/auth_provider.dart"
EDIT_PROFILE_PAGE = REPO / "huanxi/lib/modules/profile/edit_profile_page.dart"
MIGRATIONS_DIR = ROOT / "migrations/models"


def test_profile_review_model_and_migration_are_registered() -> None:
    assert PROFILE_REVIEW_MODEL.exists()

    model_text = PROFILE_REVIEW_MODEL.read_text(encoding="utf-8")
    assert "class AppUserProfileReviewApply" in model_text
    assert 'table = "app_user_profile_review_apply"' in model_text
    assert "before_snapshot" in model_text
    assert "after_snapshot" in model_text
    assert "review_items" in model_text

    init_text = APP_MODELS_INIT.read_text(encoding="utf-8")
    assert "app_user_profile_review" in init_text

    migration_text = "\n".join(path.read_text(encoding="utf-8") for path in MIGRATIONS_DIR.glob("*.py"))
    assert "app_user_profile_review_apply" in migration_text
    assert "idx_profile_review_user_status" in migration_text


def test_app_profile_update_creates_review_apply_for_guarded_fields() -> None:
    text = APP_USER_API.read_text(encoding="utf-8")

    assert "AppUserProfileReviewApply" in text
    assert 'pending", "reviewing"' in text or "pending', 'reviewing'" in text
    assert "资料修改申请已提交，请等待审核" in text
    assert "您有资料编辑申请待审核，请审核完成后再提交" in text
    assert "profile_review_status" in text
    assert "upload_user_image" in text


def test_admin_profile_review_endpoints_exist() -> None:
    text = ADMIN_APP_USER_API.read_text(encoding="utf-8")

    assert '"/profile-review/list"' in text
    assert '"/profile-review/get"' in text
    assert '"/profile-review/item/review"' in text
    assert '"/profile-review/approve-all"' in text
    assert '"/profile-review/reject-all"' in text
    assert '"/profile-review/complete"' in text
    assert "apply_approved_profile_review_items" in text


def test_admin_web_profile_review_view_and_api_exist() -> None:
    api_text = WEB_API.read_text(encoding="utf-8")

    assert "getProfileReviewList" in api_text
    assert "reviewProfileReviewItem" in api_text
    assert "approveAllProfileReviewItems" in api_text
    assert "rejectAllProfileReviewItems" in api_text
    assert "completeProfileReview" in api_text

    assert WEB_REVIEW_VIEW.exists()
    view_text = WEB_REVIEW_VIEW.read_text(encoding="utf-8")
    assert "资料编辑审核" in view_text
    assert "提交前" in view_text
    assert "提交后" in view_text
    assert "全部通过" in view_text
    assert "全部驳回" in view_text
    assert "完成审核" in view_text
    assert "审核中" in view_text


def test_operation_menu_blueprint_has_profile_review_menu_and_apis() -> None:
    text = INIT_APP.read_text(encoding="utf-8")
    migration_text = "\n".join(path.read_text(encoding="utf-8") for path in MIGRATIONS_DIR.glob("*.py"))

    assert 'name="资料编辑审核"' in text
    assert 'path="profile-review"' in text
    assert 'component="/operation/profile-review"' in text
    assert '"/api/v1/app_user/profile-review/list"' in text
    assert '"/api/v1/app_user/profile-review/complete"' in text
    assert "'资料编辑审核'" in migration_text
    assert "'profile-review'" in migration_text
    assert "'/operation/profile-review'" in migration_text
    assert "`role_menu`" in migration_text
    assert "`role_api`" in migration_text


def test_flutter_profile_update_uses_review_submit_success_message() -> None:
    auth_text = AUTH_PROVIDER.read_text(encoding="utf-8")
    page_text = EDIT_PROFILE_PAGE.read_text(encoding="utf-8")

    assert "lastProfileUpdateData" in auth_text
    assert "profile_review_status" in page_text
    assert "资料修改申请已提交，请等待审核" in page_text


def test_album_cover_and_order_changes_skip_profile_review() -> None:
    service_text = (ROOT / "app/services/profile_review_service.py").read_text(encoding="utf-8")
    app_api_text = APP_USER_API.read_text(encoding="utf-8")

    assert '"cover_url"' not in service_text.split("_REVIEW_FIELDS", 1)[1].split(")", 1)[0]
    assert '"op": "remove"' not in service_text
    assert "direct_update_data" in app_api_text
    assert "partial_direct_saved" in app_api_text
    assert "if direct_album != current_album" in app_api_text
    assert "if direct_cover != current_cover" in app_api_text


def test_admin_and_app_album_reorder_controls_exist() -> None:
    web_text = WEB_APP_USER_VIEW.read_text(encoding="utf-8")
    page_text = EDIT_PROFILE_PAGE.read_text(encoding="utf-8")

    assert "handleMoveAlbumPhoto" in web_text
    assert "上移" in web_text
    assert "下移" in web_text
    assert "_moveAlbumPhoto" in page_text
    assert "Icons.arrow_upward" in page_text
    assert "Icons.arrow_downward" in page_text
    assert "资料已保存，部分修改已提交审核" in page_text
