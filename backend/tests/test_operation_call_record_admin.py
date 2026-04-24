from app.api.v1 import v1_router
from app.core import init_app


def test_call_record_admin_route_registered() -> None:
    paths = {getattr(route, "path", "") for route in v1_router.routes}
    assert "/call_record/list" in paths


def test_operation_menu_blueprint_has_call_record_menu() -> None:
    children = init_app.build_operation_children(parent_id=100)
    assert any(menu.name == "通话记录" and menu.component == "/operation/call-record" for menu in children)
