from pathlib import Path


V1_INIT = Path("app/api/v1/__init__.py")
INIT_APP = Path("app/core/init_app.py")
RECHARGE_API = Path("app/api/v1/recharge/recharge.py")
RECHARGE_SCHEMA = Path("app/schemas/app_api.py")
RECHARGE_VIEW = Path("../backend/web/src/views/operation/recharge/index.vue")


def test_recharge_admin_route_registered() -> None:
    text = V1_INIT.read_text(encoding="utf-8")
    assert "v1_router.include_router(recharge_router, prefix=\"/recharge\", dependencies=[DependPermission])" in text


def test_operation_menu_blueprint_has_recharge_menu() -> None:
    text = INIT_APP.read_text(encoding="utf-8")
    assert "name=\"充值管理\"" in text
    assert "component=\"/operation/recharge\"" in text


def test_recharge_review_does_not_support_cancel_action() -> None:
    api_text = RECHARGE_API.read_text(encoding="utf-8")
    schema_text = RECHARGE_SCHEMA.read_text(encoding="utf-8")

    assert '"cancel"' not in api_text
    assert "cancel（取消）" not in schema_text
    assert "已取消订单" not in api_text


def test_recharge_admin_view_does_not_show_cancelled_status() -> None:
    text = RECHARGE_VIEW.read_text(encoding="utf-8")

    assert "已取消" not in text
    assert "cancelled" not in text
