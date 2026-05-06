from pathlib import Path


V1_INIT = Path("app/api/v1/__init__.py")
INIT_APP = Path("app/core/init_app.py")


def test_recharge_admin_route_registered() -> None:
    text = V1_INIT.read_text(encoding="utf-8")
    assert "v1_router.include_router(recharge_router, prefix=\"/recharge\", dependencies=[DependPermission])" in text


def test_operation_menu_blueprint_has_recharge_menu() -> None:
    text = INIT_APP.read_text(encoding="utf-8")
    assert "name=\"充值管理\"" in text
    assert "component=\"/operation/recharge\"" in text
