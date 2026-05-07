from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent

SCHEMA_SYSTEM = ROOT / "app/schemas/system.py"
APP_BOOTSTRAP = ROOT / "app/api/v1/app/bootstrap.py"
APP_WALLET = ROOT / "app/api/v1/app/wallet.py"
APP_MODELS = ROOT / "app/models/admin.py"
APP_API_SCHEMA = ROOT / "app/schemas/app_api.py"
SYSTEM_INIT = ROOT / "app/api/v1/apis/system/__init__.py"
SYSTEM_API = ROOT / "app/api/v1/apis/system/withdraw_config.py"
WEB_API = ROOT / "web/src/api/system.js"
WEB_VIEW = ROOT / "web/src/views/system/withdraw-config/index.vue"


def test_withdraw_package_schema_exists() -> None:
    text = SCHEMA_SYSTEM.read_text(encoding="utf-8")

    assert "class WithdrawPackageItem" in text
    assert "diamonds:" in text
    assert "amount:" in text
    assert "class WithdrawConfigIn" in text


def test_app_bootstrap_returns_withdraw_packages() -> None:
    text = APP_BOOTSTRAP.read_text(encoding="utf-8")

    assert 'config_map.get("withdraw_packages")' in text
    assert '"withdraw_packages": withdraw_packages' in text


def test_withdraw_apply_requires_configured_package_and_account_snapshot() -> None:
    text = APP_WALLET.read_text(encoding="utf-8")

    assert "is_configured_withdraw_amount" in text
    assert "请先配置提现档位" in text
    assert "请选择有效的提现档位" in text
    assert "WithdrawAccount" in text
    assert "payment_qr_code" in text


def test_withdraw_account_model_and_schema_exist() -> None:
    model_text = APP_MODELS.read_text(encoding="utf-8")
    schema_text = APP_API_SCHEMA.read_text(encoding="utf-8")

    assert "class WithdrawAccount" in model_text
    assert 'table = "withdraw_account"' in model_text
    assert "payment_qr_code" in model_text
    assert "class WithdrawAccountIn" in schema_text
    assert "class WithdrawAccountOut" in schema_text


def test_withdraw_config_admin_route_and_web_view_exist() -> None:
    init_text = SYSTEM_INIT.read_text(encoding="utf-8")
    web_api_text = WEB_API.read_text(encoding="utf-8")

    assert SYSTEM_API.exists()
    assert WEB_VIEW.exists()
    assert "withdraw_config_router" in init_text
    assert 'prefix="/withdraw-config"' in init_text
    assert "getWithdrawConfig" in web_api_text
    assert "updateWithdrawConfig" in web_api_text


def test_system_menu_blueprint_has_withdraw_config_menu() -> None:
    text = (ROOT / "app/core/init_app.py").read_text(encoding="utf-8")

    assert "name\": \"提现配置\"" in text
    assert "component\": \"/system/withdraw-config\"" in text
    assert "await api_controller.refresh_api()" in text
    assert "withdraw_config_menu" in text
