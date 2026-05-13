from pathlib import Path


BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _read_backend_file(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def _read_all_migrations() -> str:
    migration_dir = BACKEND_ROOT / "migrations" / "models"
    return "\n".join(path.read_text(encoding="utf-8") for path in sorted(migration_dir.glob("*.py")))


def test_balance_adjust_schema_requires_reason() -> None:
    schema_src = _read_backend_file("app/schemas/app_user.py")

    assert "class AppUserBalanceAdjustIn" in schema_src
    assert 'reason: str = Field(..., min_length=1, max_length=500' in schema_src


def test_balance_adjust_records_operator_reason_and_snapshots() -> None:
    api_src = _read_backend_file("app/api/v1/app_users/app_users.py")
    model_src = _read_backend_file("app/models/app_user_token_adjust_record.py")
    model_init_src = _read_backend_file("app/models/__init__.py")
    migrations_src = _read_all_migrations()

    assert "AppUserTokenAdjustRecord" in api_src
    assert "select_for_update()" in api_src
    assert "CTX_USER_ID.get()" in api_src
    assert "reason = req_in.reason.strip()" in api_src
    assert "before_amount" in api_src
    assert "after_amount" in api_src
    assert "operator_user_id" in api_src
    assert "operator_username" in api_src
    assert 'publish_balance_changed(int(req_in.id), source="balance_adjust")' in api_src

    assert "class AppUserTokenAdjustRecord" in model_src
    assert 'table = "app_user_token_adjust_record"' in model_src
    assert "app_user_id" in model_src
    assert "operator_user_id" in model_src
    assert "operator_username" in model_src
    assert "asset_type" in model_src
    assert "action" in model_src
    assert "before_amount" in model_src
    assert "after_amount" in model_src
    assert "reason" in model_src
    assert "app_user_token_adjust_record" in model_init_src

    assert "CREATE TABLE IF NOT EXISTS `app_user_token_adjust_record`" in migrations_src
    assert "`operator_user_id`" in migrations_src
    assert "`before_amount`" in migrations_src
    assert "`after_amount`" in migrations_src
    assert "`reason`" in migrations_src


def test_admin_bill_includes_token_adjust_but_app_wallet_does_not() -> None:
    admin_api_src = _read_backend_file("app/api/v1/app_users/app_users.py")
    app_wallet_src = _read_backend_file("app/api/v1/app/wallet.py")
    web_view_src = _read_backend_file("web/src/views/operation/app-user/index.vue")

    assert "token_adjust_records" in admin_api_src
    assert '"biz_type": "token_adjust"' in admin_api_src
    assert '"token_adjust"' in admin_api_src
    assert "后台增加" in admin_api_src
    assert "后台扣除" in admin_api_src
    assert 'allowed_types = {"recharge", "call", "gift", "withdraw", "im_text", "call_fee", "gift_fee", "token_adjust"}' in admin_api_src

    assert "token_adjust" not in app_wallet_src

    assert "后台调整" in web_view_src
    assert "token_adjust" in web_view_src


def test_token_adjust_record_admin_route_web_api_and_menu_exist() -> None:
    api_init_src = _read_backend_file("app/api/v1/__init__.py")
    route_src = _read_backend_file("app/api/v1/token_adjust_record/__init__.py")
    list_src = _read_backend_file("app/api/v1/token_adjust_record/token_adjust_record.py")
    web_api_src = _read_backend_file("web/src/api/index.js")
    web_view_src = _read_backend_file("web/src/views/operation/token-adjust-record/index.vue")
    init_app_src = _read_backend_file("app/core/init_app.py")

    assert "token_adjust_record_router" in api_init_src
    assert 'prefix="/token_adjust_record"' in api_init_src
    assert "token_adjust_record_router" in route_src

    assert '@router.get("/list"' in list_src
    assert "AppUserTokenAdjustRecord" in list_src
    assert "operator_user_id" in list_src
    assert "app_user_id" in list_src
    assert "start_time" in list_src
    assert "end_time" in list_src

    assert "getTokenAdjustRecordList" in web_api_src
    assert "/token_adjust_record/list" in web_api_src
    assert "代币修改记录" in web_view_src
    assert "getTokenAdjustRecordList" in web_view_src
    assert "operator_user_id" in web_view_src
    assert "reason" in web_view_src

    assert 'name="代币修改记录"' in init_app_src
    assert 'path="token-adjust-record"' in init_app_src
    assert 'component="/operation/token-adjust-record"' in init_app_src
    assert '"/api/v1/token_adjust_record/list"' in init_app_src
