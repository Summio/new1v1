"""验证轮询接口已从通话路由中移除。"""

from app.api.v1.app.call import router


def test_removed_polling_routes_not_registered() -> None:
    paths = {route.path for route in router.routes}
    assert "/call/session/current" not in paths
    assert "/call/status" not in paths
    assert "/call/renew" not in paths
