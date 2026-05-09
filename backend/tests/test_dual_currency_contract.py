from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _read_backend_file(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def test_wallet_balance_schema_exposes_token_names() -> None:
    content = _read_backend_file("app/schemas/app_api.py")

    assert 'coin_name: str = "金币"' in content
    assert 'diamond_name: str = "钻石"' in content


def test_recharge_callback_credits_coins_not_diamonds() -> None:
    content = _read_backend_file("app/api/v1/app/wallet.py")

    assert 'coins=F("coins") + order.amount' in content
    assert 'diamonds=F("diamonds") + order.amount' not in content


def test_gift_send_credits_receiver_diamonds() -> None:
    content = _read_backend_file("app/api/v1/app/gift.py")

    assert "certified_user_income_diamonds = (" in content
    assert "gift_certified_user_share_bps" in content
    assert 'diamonds=F("diamonds") + certified_user_income_diamonds' in content


def test_call_end_credits_certified_user_diamonds() -> None:
    content = _read_backend_file("app/api/v1/app/call.py")

    assert "settle_call_certified_user_income_once(" in content


def test_call_creation_snapshots_income_certified_user_and_share() -> None:
    content = _read_backend_file("app/api/v1/app/call.py")

    assert "certified_user_share_bps = await get_certified_user_share_bps()" in content
    assert "income_certified_user_id=income_certified_user_id" in content
    assert "certified_user_share_bps=certified_user_share_bps" in content


def test_call_record_model_exposes_certified_user_income_fields() -> None:
    content = _read_backend_file("app/models/admin.py")

    assert "income_certified_user_id" in content
    assert "certified_user_share_bps" in content
    assert "certified_user_income_diamonds" in content
    assert "income_settled_at" in content


def test_watchdog_settlement_records_certified_user_income_for_im_trace() -> None:
    content = _read_backend_file("app/core/call_watchdog.py")

    assert "settle_call_certified_user_income_once(" in content
    assert "certified_user_balance_pushes" in content


def test_admin_system_config_alias_matches_spec_path() -> None:
    routes_content = _read_backend_file("app/api/v1/__init__.py")
    config_content = _read_backend_file("app/api/v1/system_config/system_config.py")

    assert 'prefix="/apis"' in routes_content
    assert '@spec_router.get("/system-config"' in config_content
    assert '@spec_router.put("/system-config/{cfg_key}"' in config_content


def test_admin_web_exposes_trace_and_income_controls() -> None:
    config_content = _read_backend_file("web/src/views/system/config/index.vue")
    call_record_content = _read_backend_file("web/src/views/operation/call-record/index.vue")
    app_user_content = _read_backend_file("web/src/views/operation/app-user/index.vue")

    assert "im_call_trace_enabled" in config_content
    assert "im_admin_identifier" in config_content
    assert "call_certified_user_share_bps" in config_content
    assert "im_text_message_certified_user_share_bps" in config_content
    assert "step: 0.01" in config_content
    assert "认证用户收益(钻石)" in call_record_content
    assert "certified_user_income_diamonds" in call_record_content
    assert "收益结算时间" in call_record_content
    assert "income_settled_at" in call_record_content
    assert "认证用户收益(钻石)" in app_user_content
    assert "certified_user_income_diamonds" in app_user_content
    assert "收益结算时间" in app_user_content
    assert "income_settled_at" in app_user_content

def test_app_displays_certified_user_call_price() -> None:
    content = (BACKEND_ROOT.parent / "huanxi/lib/modules/home/home_page.dart").read_text(
        encoding="utf-8"
    )

    assert "certifiedUser.callPrice?.toStringAsFixed(0)" in content
    assert "anchor.diamonds ?? 0" not in content


def test_call_certified_user_share_defaults_to_existing_commission_rate() -> None:
    original_migration_text = _read_backend_file("migrations/models/19_20260504110000_dual_currency_columns_seed.py")
    rename_migration_text = _read_backend_file("migrations/models/39_20260509100000_certified_user_income_fields.py")
    call_content = _read_backend_file("app/api/v1/app/call.py")
    watchdog_content = _read_backend_file("app/core/call_watchdog.py")

    assert "DEFAULT 5000" in original_migration_text
    assert "SELECT 'call_anchor_share_bps', '5000'" in original_migration_text
    assert "SELECT 'call_certified_user_share_bps', '5000'" in rename_migration_text
    assert "DEFAULT_CERTIFIED_USER_SHARE_BPS = 5000" in call_content
    assert "DEFAULT_CERTIFIED_USER_SHARE_BPS = 5000" in watchdog_content


def test_call_income_migration_is_idempotent_for_existing_columns() -> None:
    original_migration_text = _read_backend_file("migrations/models/19_20260504110000_dual_currency_columns_seed.py")
    rename_migration_text = _read_backend_file("migrations/models/39_20260509100000_certified_user_income_fields.py")

    assert "INFORMATION_SCHEMA.COLUMNS" in original_migration_text
    assert "COLUMN_NAME = 'income_anchor_user_id'" in original_migration_text
    assert "COLUMN_NAME = 'anchor_share_bps'" in original_migration_text
    assert "COLUMN_NAME = 'anchor_income_diamonds'" in original_migration_text
    assert "COLUMN_NAME = 'income_settled_at'" in original_migration_text
    assert "PREPARE stmt FROM @sql" in original_migration_text
    assert "INFORMATION_SCHEMA.COLUMNS" in rename_migration_text
    assert "CHANGE COLUMN `income_anchor_user_id` `income_certified_user_id`" in rename_migration_text
    assert "CHANGE COLUMN `anchor_share_bps` `certified_user_share_bps`" in rename_migration_text
    assert "CHANGE COLUMN `anchor_income_diamonds` `certified_user_income_diamonds`" in rename_migration_text
    assert "PREPARE stmt FROM @sql" in rename_migration_text


def test_income_service_is_idempotent_and_locks_certified_user_row() -> None:
    content = _read_backend_file("app/services/call_income_service.py")

    assert "async def settle_call_certified_user_income_once" in content
    assert 'if getattr(call_record, "income_settled_at", None) is not None' in content
    assert ".select_for_update()" in content
    assert 'diamonds=F("diamonds") + certified_user_income' in content


def test_app_user_dual_currency_migration_is_idempotent() -> None:
    migration_text = _read_backend_file("migrations/models/20_20260504190000_app_user_dual_currency_idempotent.py")

    assert "COLUMN_NAME = 'coins'" in migration_text
    assert "COLUMN_NAME = 'diamonds'" in migration_text
    assert "COLUMN_NAME = 'frozen_diamonds'" in migration_text
    assert "COLUMN_NAME = 'balance'" in migration_text
    assert "COLUMN_NAME = 'frozen_balance'" in migration_text
    assert "MODIFY COLUMN `coins` BIGINT" in migration_text
    assert "MODIFY COLUMN `diamonds` BIGINT" in migration_text
    assert "MODIFY COLUMN `frozen_diamonds` BIGINT" in migration_text
    assert "SET `balance` = `coins`" in migration_text
    assert "SET `frozen_balance` = `frozen_diamonds`" in migration_text
    assert "PREPARE stmt FROM @sql" in migration_text


def test_migrations_create_dual_currency_columns() -> None:
    migration_text = "\n".join(
        path.read_text(encoding="utf-8") for path in sorted((BACKEND_ROOT / "migrations/models").glob("*.py"))
    )

    assert "ADD `coins`" in migration_text
    assert "ADD `diamonds`" in migration_text
    assert "ADD `frozen_diamonds`" in migration_text

