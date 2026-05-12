from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _read_backend_file(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def test_models_expose_service_fee_fields() -> None:
    content = _read_backend_file("app/models/admin.py")

    assert "service_fee_processed_chargeable_minutes" in content
    assert "service_fee_payer_rate_bps" in content
    assert "service_fee_income_rate_bps" in content
    assert "service_fee_payer_expected_coins" in content
    assert "service_fee_income_actual_diamonds" in content
    assert "service_fee_sender_status" in content


def test_gift_send_is_single_quantity_across_schema_backend_and_app() -> None:
    schema_content = _read_backend_file("app/schemas/app_api.py")
    gift_api_content = _read_backend_file("app/api/v1/app/gift.py")
    app_provider_content = (BACKEND_ROOT.parent / "huanxi/lib/app/providers/gift_provider.dart").read_text(
        encoding="utf-8"
    )

    assert "quantity: int = Field(default=1, ge=1, le=1" in schema_content
    assert "if quantity != 1:" in gift_api_content
    assert "'quantity': 1" in app_provider_content
    assert "'quantity': quantity" not in app_provider_content


def test_watchdog_and_call_end_wire_service_fee_processing() -> None:
    watchdog_content = _read_backend_file("app/core/call_watchdog.py")
    call_content = _read_backend_file("app/api/v1/app/call.py")
    income_content = _read_backend_file("app/services/call_income_service.py")

    assert "_apply_incremental_call_service_fee" in watchdog_content
    assert "service_fee_processed_chargeable_minutes" in watchdog_content
    assert "apply_call_service_fee_final_adjustment" in call_content
    assert "service_fee_diamonds" in income_content


def test_backend_and_web_expose_fee_bill_entrypoints() -> None:
    api_router_content = _read_backend_file("app/api/v1/__init__.py")
    api_index_content = _read_backend_file("web/src/api/index.js")
    init_app_content = _read_backend_file("app/core/init_app.py")
    fee_bill_view = BACKEND_ROOT / "web/src/views/operation/fee-bill/index.vue"

    assert "fee_bill_router" in api_router_content
    assert 'prefix="/fee_bill"' in api_router_content
    assert "getFeeBillList" in api_index_content
    assert "手续费账单" in init_app_content
    assert "fee-bill" in init_app_content
    assert fee_bill_view.exists()


def test_app_user_bill_supports_service_fee_biz_types() -> None:
    content = _read_backend_file("app/api/v1/app_users/app_users.py")

    assert '"call_fee"' in content
    assert '"gift_fee"' in content
