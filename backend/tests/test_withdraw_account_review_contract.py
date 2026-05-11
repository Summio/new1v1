from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent

APP_MODELS = ROOT / "app/models/admin.py"
APP_SCHEMA = ROOT / "app/schemas/app_api.py"
APP_WALLET = ROOT / "app/api/v1/app/wallet.py"
WITHDRAW_API = ROOT / "app/api/v1/withdraw/withdraw.py"
INIT_APP = ROOT / "app/core/init_app.py"
WEB_API = ROOT / "web/src/api/index.js"
WEB_VIEW = ROOT / "web/src/views/operation/withdraw-account/index.vue"
FLUTTER_PROVIDER = REPO / "huanxi/lib/app/providers/wallet_provider.dart"
FLUTTER_WITHDRAW_PAGE = REPO / "huanxi/lib/modules/profile/withdraw_page.dart"
FLUTTER_ACCOUNT_PAGE = REPO / "huanxi/lib/modules/profile/withdraw_account_page.dart"
MIGRATIONS = ROOT / "migrations/models"


def test_withdraw_account_model_has_review_fields_and_single_account_constraint() -> None:
    text = APP_MODELS.read_text(encoding="utf-8")
    account_section = text.split("class WithdrawAccount", 1)[1].split("class Meta:", 1)[0]

    assert "user_id = fields.BigIntField" in account_section
    assert "unique=True" in account_section
    assert "status = fields.CharField" in account_section
    assert 'default="pending"' in account_section
    assert "reviewed_by = fields.BigIntField" in account_section
    assert "reviewed_at = fields.DatetimeField" in account_section
    assert "review_remark = fields.CharField" in account_section


def test_withdraw_account_schemas_expose_app_and_admin_review_contracts() -> None:
    text = APP_SCHEMA.read_text(encoding="utf-8")

    assert "class WithdrawAccountOut" in text
    assert "status: str" in text
    assert "review_remark: str" in text
    assert "reviewed_at: Optional[datetime]" in text
    assert "can_withdraw: bool" in text
    assert "class WithdrawAccountListItem" in text
    assert "class WithdrawAccountReviewIn" in text
    assert "account_id: int" in text


def test_app_withdraw_account_flow_enforces_review_state_machine() -> None:
    text = APP_WALLET.read_text(encoding="utf-8")

    assert 'if account.status == "pending"' in text
    assert "提现账户待审核中，请勿重复提交" in text
    assert 'account.status == "approved"' in text
    assert "withdraw_account_payload_changed" in text
    assert 'status="pending"' in text
    assert 'status="approved"' in text
    assert 'can_withdraw=account.status == "approved"' in text


def test_app_withdraw_apply_uses_only_approved_account_snapshot() -> None:
    text = APP_WALLET.read_text(encoding="utf-8")
    apply_section = text.split("async def withdraw_apply(req_in: WithdrawApplyIn):", 1)[1].split(
        '@router.get("/wallet/transactions"',
        1,
    )[0]

    assert 'WithdrawAccount.filter(user_id=user_id, status="approved")' in apply_section
    assert "请先提交并通过提现账户审核" in apply_section
    assert "real_name=account.real_name" in apply_section
    assert "account_no=account.account_no" in apply_section
    assert "payment_qr_code=account.payment_qr_code" in apply_section
    assert "account.real_name = real_name" not in apply_section
    assert "WithdrawAccount.create" not in apply_section


def test_admin_withdraw_account_review_api_and_web_view_exist() -> None:
    api_text = WITHDRAW_API.read_text(encoding="utf-8")
    web_api_text = WEB_API.read_text(encoding="utf-8")

    assert '@router.get("/account/list"' in api_text
    assert '@router.post("/account/review"' in api_text
    assert "WithdrawAccountListItem" in api_text
    assert "WithdrawAccountReviewIn" in api_text
    assert "getWithdrawAccountList" in web_api_text
    assert "reviewWithdrawAccount" in web_api_text
    assert WEB_VIEW.exists()

    view_text = WEB_VIEW.read_text(encoding="utf-8")
    assert "提现账户审核" in view_text
    assert "pending" in view_text
    assert "getWithdrawAccountList" in view_text
    assert "reviewWithdrawAccount" in view_text
    assert "收款码" in view_text


def test_operation_menu_and_permissions_include_withdraw_account_review() -> None:
    text = INIT_APP.read_text(encoding="utf-8")

    assert 'name="提现账户审核"' in text
    assert 'path="withdraw-account"' in text
    assert 'component="/operation/withdraw-account"' in text
    assert '"/api/v1/withdraw/account/list"' in text
    assert '"/api/v1/withdraw/account/review"' in text


def test_migration_adds_review_fields_and_marks_existing_accounts_approved() -> None:
    migration_text = "\n".join(
        path.read_text(encoding="utf-8") for path in MIGRATIONS.glob("*withdraw_account_review*.py")
    )

    assert "ALTER TABLE `withdraw_account` ADD `status`" in migration_text
    assert "ALTER TABLE `withdraw_account` ADD `reviewed_by`" in migration_text
    assert "ALTER TABLE `withdraw_account` ADD `reviewed_at`" in migration_text
    assert "ALTER TABLE `withdraw_account` ADD `review_remark`" in migration_text
    assert "UPDATE `withdraw_account` SET `status` = 'approved'" in migration_text
    assert "'提现账户审核'" in migration_text
    assert "'/operation/withdraw-account'" in migration_text


def test_flutter_withdraw_account_review_state_is_surface_and_enforced() -> None:
    provider_text = FLUTTER_PROVIDER.read_text(encoding="utf-8")
    withdraw_page_text = FLUTTER_WITHDRAW_PAGE.read_text(encoding="utf-8")
    account_page_text = FLUTTER_ACCOUNT_PAGE.read_text(encoding="utf-8")
    edit_account_section = withdraw_page_text.split("Future<void> _editAccount() async", 1)[1].split(
        "Future<void> _submitWithdraw() async",
        1,
    )[0]

    assert "status" in provider_text
    assert "canWithdraw" in provider_text
    assert "isPending" in provider_text
    assert "isApproved" in provider_text
    assert "isRejected" in provider_text
    assert "账户审核中" in withdraw_page_text
    assert "账户审核未通过" in withdraw_page_text
    assert "_account.canWithdraw" in withdraw_page_text
    assert "saveWithdrawAccount" not in withdraw_page_text
    assert "提交审核" in account_page_text
    assert "if (_account.isPending)" in edit_account_section
    assert "提现账户待审核中，请勿重复提交" in edit_account_section
    assert "return;" in edit_account_section
