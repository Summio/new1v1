from decimal import Decimal
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.schemas.app_api import IMTextChargeIn
from app.schemas.system import IMTextBillingConfigIn
from app.services.im_text_billing_service import (
    DEFAULT_IM_TEXT_CERTIFIED_USER_SHARE_BPS,
    DEFAULT_IM_TEXT_PRICE,
    calc_im_text_certified_user_income_diamonds,
    parse_im_text_billing_config,
    should_charge_im_text_message,
    should_credit_im_text_receiver,
)

BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _read_backend_file(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def test_im_text_billing_config_defaults_are_safe() -> None:
    config = parse_im_text_billing_config({})

    assert config.enabled is False
    assert config.price == DEFAULT_IM_TEXT_PRICE
    assert config.certified_user_share_bps == DEFAULT_IM_TEXT_CERTIFIED_USER_SHARE_BPS


def test_im_text_billing_config_rejects_enabled_zero_price() -> None:
    with pytest.raises(ValidationError):
        IMTextBillingConfigIn(enabled=True, price=0, certified_user_share_bps=5000)


def test_im_text_billing_config_rejects_invalid_share() -> None:
    with pytest.raises(ValidationError):
        IMTextBillingConfigIn(enabled=False, price=0, certified_user_share_bps=10001)


def test_im_text_certified_user_income_keeps_two_decimal_precision() -> None:
    assert calc_im_text_certified_user_income_diamonds(1, 5000) == Decimal("0.50")
    assert calc_im_text_certified_user_income_diamonds(99, 5250) == Decimal("51.98")


def test_im_text_charges_normal_sender_to_normal_receiver_without_income() -> None:
    assert should_charge_im_text_message(
        enabled=True,
        price=1,
        sender_is_certified_user=False,
        receiver_is_certified_user=False,
    )
    assert not should_credit_im_text_receiver(receiver_is_certified_user=False)


def test_im_text_charge_request_requires_request_id() -> None:
    item = IMTextChargeIn(receiver_user_id=2, request_id="req_123456")
    assert item.receiver_user_id == 2

    with pytest.raises(ValidationError):
        IMTextChargeIn(receiver_user_id=2, request_id="short")


def test_im_text_config_route_contract_exists() -> None:
    content = _read_backend_file("app/api/v1/apis/system/__init__.py")
    assert "im_text_billing_config_router" in content
    assert 'prefix="/im-text-billing-config"' in content


def test_im_text_config_api_uses_system_config_and_clears_cache() -> None:
    content = _read_backend_file("app/api/v1/apis/system/im_text_billing_config.py")

    assert "@router.get(" in content
    assert "@router.put(" in content
    assert "SystemConfig.get_all_as_dict" in content
    assert "SYSTEM_CONFIG_CACHE_KEY" in content
    assert "im_text_message_billing_enabled" in content
    assert "im_text_message_price" in content
    assert "im_text_message_certified_user_share_bps" in content


def test_im_text_charge_model_and_migration_exist() -> None:
    model_content = _read_backend_file("app/models/admin.py")
    migration_content = _read_backend_file("migrations/models/23_20260507100000_im_text_message_billing.py")
    decimal_migration_content = _read_backend_file("migrations/models/26_20260507231620_update.py")
    rename_migration_content = _read_backend_file("migrations/models/39_20260509100000_certified_user_income_fields.py")

    assert "class ImTextMessageChargeRecord" in model_content
    assert 'table = "im_text_message_charge_record"' in model_content
    assert 'unique_together = (("sender_id", "request_id"),)' in model_content
    assert "DecimalField" in model_content
    assert "CREATE TABLE IF NOT EXISTS `im_text_message_charge_record`" in migration_content
    assert "im_text_message_billing_enabled" in migration_content
    assert "DECIMAL(18,2)" in decimal_migration_content
    assert "`anchor_income_diamonds` `certified_user_income_diamonds`" in rename_migration_content


def test_im_text_charge_service_uses_atomic_balance_updates() -> None:
    content = _read_backend_file("app/services/im_text_billing_service.py")

    assert "async def charge_im_text_message" in content
    assert 'coins=F("coins") - price' in content
    assert 'diamonds=F("diamonds") + certified_user_income_diamonds' in content
    assert "in_transaction()" in content
    assert "coins__gte=price" in content


def test_im_text_charge_endpoint_contract_exists() -> None:
    content = _read_backend_file("app/api/v1/app/im.py")

    assert '@router.post("/im/text-charge"' in content
    assert "IMTextChargeIn" in content
    assert "charge_im_text_message" in content
    assert "IMTextBillingError" in content
    assert "Fail(code=exc.code" in content


def test_bootstrap_returns_im_text_billing_config() -> None:
    content = _read_backend_file("app/api/v1/app/bootstrap.py")

    assert "parse_im_text_billing_config" in content
    assert '"im_text_billing"' in content or "'im_text_billing'" in content


def test_wallet_transactions_include_im_text_records() -> None:
    content = _read_backend_file("app/api/v1/app/wallet.py")

    assert "im_text_message_charge_record" in content
    assert "文字聊天收益" in content
    assert "文字聊天" in content


def test_admin_user_bill_include_im_text_filter() -> None:
    content = _read_backend_file("app/api/v1/app_users/app_users.py")

    assert "im_text" in content
    assert "ImTextMessageChargeRecord" in content
    assert '"biz_type": "im_text"' in content


def test_admin_web_im_text_billing_page_removed() -> None:
    api_content = _read_backend_file("web/src/api/system.js")
    menu_content = _read_backend_file("app/core/init_app.py")
    page_path = Path("web/src/views/system/im-text-billing/index.vue")

    assert "getIMTextBillingConfig" not in api_content
    assert "updateIMTextBillingConfig" not in api_content
    assert not page_path.exists()
    assert 'Menu.filter(path="im-text-billing", component="/system/im-text-billing").delete()' in menu_content
    assert 'component": "/system/im-text-billing"' not in menu_content
