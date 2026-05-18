from datetime import timedelta
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.core.time_utils import now_local_naive
from app.schemas.system import VipConfigIn, VipPackageItem
from app.services.im_text_billing_service import should_charge_im_text_message
from app.services.vip_service import (
    create_vip_order_no,
    dump_vip_package,
    resolve_next_vip_expires_at,
)

BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _read_backend_file(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def test_vip_package_amount_uses_cent_integer() -> None:
    item = VipPackageItem(amount=1990, duration_days=30, label="月卡")

    assert item.amount == 1990
    assert dump_vip_package(item)["amount"] == 1990


def test_vip_package_rejects_invalid_cent_amount() -> None:
    with pytest.raises(ValidationError):
        VipPackageItem(amount=0, duration_days=30, label="低价")

    with pytest.raises(ValidationError):
        VipPackageItem(amount=-1, duration_days=30, label="负数")


def test_vip_config_requires_packages() -> None:
    with pytest.raises(ValidationError):
        VipConfigIn(packages=[])


def test_vip_renewal_stacks_from_existing_expiry() -> None:
    now = now_local_naive()
    current_expiry = now + timedelta(days=10)

    next_expiry = resolve_next_vip_expires_at(
        current_expires_at=current_expiry,
        duration_days=30,
        now=now,
    )

    assert next_expiry == current_expiry + timedelta(days=30)


def test_vip_renewal_starts_now_when_expired() -> None:
    now = now_local_naive()
    current_expiry = now - timedelta(days=1)

    next_expiry = resolve_next_vip_expires_at(
        current_expires_at=current_expiry,
        duration_days=30,
        now=now,
    )

    assert next_expiry == now + timedelta(days=30)


def test_vip_sender_is_not_charged_for_im_text() -> None:
    assert not should_charge_im_text_message(
        enabled=True,
        price=1,
        sender_is_certified_user=False,
        sender_is_vip=True,
        receiver_is_certified_user=True,
        receiver_is_customer_service=False,
    )


def test_vip_order_no_is_distinct_from_recharge_order() -> None:
    order_no = create_vip_order_no(now=now_local_naive(), random_hex="ABCDEF12")

    assert order_no.startswith("V")
    assert "ABCDEF12" in order_no


def test_vip_backend_contract_files_are_registered() -> None:
    model_content = _read_backend_file("app/models/admin.py")
    system_router = _read_backend_file("app/api/v1/apis/system/__init__.py")
    app_router = _read_backend_file("app/api/v1/app/__init__.py")
    bootstrap = _read_backend_file("app/api/v1/app/bootstrap.py")
    vip_api = _read_backend_file("app/api/v1/app/vip.py")

    assert "vip_expires_at" in _read_backend_file("app/models/app_user.py")
    assert "class VipOrder" in model_content
    assert 'table = "vip_order"' in model_content
    assert "vip_config_router" in system_router
    assert 'prefix="/vip-config"' in system_router
    assert "vip_router" in app_router
    assert '"/vip/order/callback"' in vip_api
    assert '"vip_packages"' in bootstrap or "'vip_packages'" in bootstrap


def test_vip_admin_web_contract_exists() -> None:
    api_content = _read_backend_file("web/src/api/system.js")
    page_path = BACKEND_ROOT / "web/src/views/system/vip-config/index.vue"
    user_page = _read_backend_file("web/src/views/operation/app-user/index.vue")

    assert "getVipConfig" in api_content
    assert "updateVipConfig" in api_content
    assert page_path.exists()
    page_content = page_path.read_text(encoding="utf-8")
    assert "amount" in page_content
    assert "/ 100" in page_content
    assert "vip_expires_at" in user_page
