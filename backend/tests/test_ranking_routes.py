import importlib
import sys
from pathlib import Path

import pytest

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.api.v1 import v1_router  # noqa: E402
from app.core import init_app  # noqa: E402

ranking_menu_migration = importlib.import_module("migrations.models.36_20260508173000_ranking_admin_menu")


def test_ranking_routes_are_registered() -> None:
    paths = {getattr(route, "path", "") for route in v1_router.routes}
    assert "/app/ranking/list" in paths
    assert "/ranking/list" in paths
    assert "/ranking/refresh" in paths
    assert "/ranking/config" in paths


def test_operation_menu_blueprint_has_ranking_menu() -> None:
    children = init_app.build_operation_children(parent_id=100)
    assert any(menu.name == "排行榜" and menu.component == "/operation/ranking" for menu in children)


@pytest.mark.asyncio
async def test_ranking_menu_migration_backfills_menu_and_permissions() -> None:
    sql = await ranking_menu_migration.upgrade(None)

    assert "'排行榜'" in sql
    assert "'/operation/ranking'" in sql
    assert "INSERT IGNORE INTO `role_menu`" in sql
    assert "INSERT IGNORE INTO `role_api`" in sql
    assert "'/api/v1/ranking/list'" in sql
    assert "'/api/v1/ranking/refresh'" in sql
    assert "'/api/v1/ranking/config'" in sql
