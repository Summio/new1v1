from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent

WITHDRAW_API = ROOT / "app/api/v1/withdraw/withdraw.py"
APP_WALLET = ROOT / "app/api/v1/app/wallet.py"
APP_MODELS = ROOT / "app/models/admin.py"
APP_SCHEMA = ROOT / "app/schemas/app_api.py"
INIT_APP = ROOT / "app/core/init_app.py"
WEB_API = ROOT / "web/src/api/index.js"
WEB_VIEW = ROOT / "web/src/views/operation/withdraw/index.vue"
FLUTTER_ENDPOINTS = REPO / "huanxi/lib/core/constants/api_endpoints.dart"
FLUTTER_ROUTER = REPO / "huanxi/lib/app/routes/app_router.dart"
FLUTTER_WITHDRAW_PAGE = REPO / "huanxi/lib/modules/profile/withdraw_page.dart"


def test_admin_withdraw_review_is_single_step_paid_or_rejected() -> None:
    text = WITHDRAW_API.read_text(encoding="utf-8")

    assert 'withdraw.status = "paid"' in text
    assert 'withdraw.status = "approved"' not in text
    assert 'diamonds=F("diamonds") + withdraw.amount' not in text.split('if action == "reject":', 1)[-1].split(
        'withdraw.status = "rejected"', 1
    )[-1]
    assert 'review_remark' in text
    assert 'processed_by' in text


def test_withdraw_apply_has_review_audit_fields() -> None:
    text = APP_MODELS.read_text(encoding="utf-8")

    assert "processed_by" in text
    assert "review_remark" in text
    assert "pending/paid/rejected" in text


def test_admin_withdraw_list_returns_full_management_fields() -> None:
    text = APP_SCHEMA.read_text(encoding="utf-8")

    assert "account_no:" in text
    assert "review_remark:" in text
    assert "processed_by:" in text


def test_admin_withdraw_list_uses_existing_app_user_name_fields() -> None:
    text = WITHDRAW_API.read_text(encoding="utf-8")

    assert ".username" not in text
    assert ".nickname" in text
    assert ".phone" in text


def test_app_withdraw_uses_wallet_transactions_for_diamond_expense() -> None:
    wallet_text = APP_WALLET.read_text(encoding="utf-8")
    schema_text = APP_SCHEMA.read_text(encoding="utf-8")

    assert '@router.get("/withdraw/records"' not in wallet_text
    assert "class WithdrawRecordItem" not in schema_text
    assert "class WithdrawRecordListOut" not in schema_text
    assert 'FROM withdraw_apply WHERE user_id = {placeholder}' in wallet_text
    assert '"withdraw": "提现申请"' in wallet_text
    assert "status AS status" in wallet_text
    assert "status: str = \"\"" in schema_text
    assert "account_no AS gift_name" in wallet_text


def test_operation_menu_blueprint_has_withdraw_management_menu() -> None:
    text = INIT_APP.read_text(encoding="utf-8")

    assert 'name="提现管理"' in text
    assert 'path="withdraw"' in text
    assert 'component="/operation/withdraw"' in text
    assert '"/api/v1/withdraw/review"' in text


def test_admin_web_withdraw_management_view_and_api_exist() -> None:
    api_text = WEB_API.read_text(encoding="utf-8")

    assert WEB_VIEW.exists()
    assert "getWithdrawList" in api_text
    assert "reviewWithdrawApply" in api_text
    view_text = WEB_VIEW.read_text(encoding="utf-8")
    assert "确认已打款" in view_text
    assert "收款码" in view_text
    assert "已驳回" in view_text


def test_flutter_withdraw_detail_keeps_diamond_transactions_route() -> None:
    endpoints_text = FLUTTER_ENDPOINTS.read_text(encoding="utf-8")
    router_text = FLUTTER_ROUTER.read_text(encoding="utf-8")
    withdraw_page_text = FLUTTER_WITHDRAW_PAGE.read_text(encoding="utf-8")

    assert "withdrawRecords" not in endpoints_text
    assert "withdrawRecords" not in router_text
    assert not (REPO / "huanxi/lib/modules/profile/withdraw_records_page.dart").exists()
    assert "AppRoutes.diamondTransactions" in withdraw_page_text
