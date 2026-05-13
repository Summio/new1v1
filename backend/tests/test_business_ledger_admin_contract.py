import json
from pathlib import Path
from unittest.mock import AsyncMock

import pytest

from app.api.v1 import v1_router
from app.api.v1.business_ledger.business_ledger import list_business_ledger
from app.core import init_app


BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _read_backend_file(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def test_business_ledger_admin_route_registered() -> None:
    paths = {getattr(route, "path", "") for route in v1_router.routes}

    assert "/business_ledger/list" in paths


def test_business_ledger_operation_menu_and_permission_seed_exist() -> None:
    children = init_app.build_operation_children(parent_id=100)
    init_app_src = _read_backend_file("app/core/init_app.py")

    assert any(
        menu.name == "全量业务流水"
        and menu.path == "business-ledger"
        and menu.component == "/operation/business-ledger"
        for menu in children
    )
    assert '"business-ledger"' in init_app_src
    assert '"/api/v1/business_ledger/list"' in init_app_src
    assert "sync_business_ledger_admin_entries" in init_app_src


def test_business_ledger_web_api_and_page_exist() -> None:
    web_api_src = _read_backend_file("web/src/api/index.js")
    web_view_src = _read_backend_file("web/src/views/operation/business-ledger/index.vue")

    assert "getBusinessLedgerList" in web_api_src
    assert "/business_ledger/list" in web_api_src

    for expected in [
        "全量业务流水",
        "用户ID",
        "关联用户ID",
        "资产",
        "方向",
        "业务类型",
        "业务ID",
        "金币",
        "钻石",
        "getBusinessLedgerList",
    ]:
        assert expected in web_view_src


def test_business_ledger_backend_contract_terms_exist() -> None:
    list_src = _read_backend_file("app/api/v1/business_ledger/business_ledger.py")

    for expected in [
        '@router.get("/list"',
        "UNION ALL",
        "asset_type",
        "direction",
        "biz_type",
        "related_user_id",
        "event_time",
        "created_at",
        "operator_username",
        "app_user_token_adjust_record",
        "recharge_order",
        "call_record",
        "gift_record",
        "im_text_message_charge_record",
        "withdraw_apply",
    ]:
        assert expected in list_src


async def _response_json(response) -> dict:
    return json.loads(response.body.decode("utf-8"))


@pytest.mark.asyncio
async def test_business_ledger_rejects_invalid_filters_before_database_access() -> None:
    default_args = {
        "asset_type": "",
        "direction": "all",
        "biz_type": "",
        "start_time": "",
        "end_time": "",
    }

    invalid_asset = await list_business_ledger(**{**default_args, "asset_type": "cash"})
    invalid_direction = await list_business_ledger(**{**default_args, "direction": "both"})
    invalid_biz_type = await list_business_ledger(**{**default_args, "biz_type": "unknown"})
    invalid_time = await list_business_ledger(**{**default_args, "start_time": "not-a-time"})

    assert invalid_asset.status_code == 400
    assert (await _response_json(invalid_asset))["msg"] == "asset_type 仅支持 coins/diamonds"
    assert invalid_direction.status_code == 400
    assert (await _response_json(invalid_direction))["msg"] == "direction 仅支持 all/income/expense"
    assert invalid_biz_type.status_code == 400
    assert invalid_time.status_code == 400


@pytest.mark.asyncio
async def test_business_ledger_admin_entries_sync_even_when_startup_seed_disabled(monkeypatch) -> None:
    init_db = AsyncMock()
    init_superuser = AsyncMock()
    init_menus = AsyncMock()
    init_apis = AsyncMock()
    init_roles = AsyncMock()
    sync_business_ledger_admin_entries = AsyncMock()
    monkeypatch.setattr(init_app.settings, "AUTO_MIGRATE_ON_STARTUP", False, raising=False)
    monkeypatch.setattr(init_app.settings, "AUTO_SEED_ON_STARTUP", False, raising=False)
    monkeypatch.setattr(init_app, "init_db", init_db)
    monkeypatch.setattr(init_app, "init_superuser", init_superuser)
    monkeypatch.setattr(init_app, "init_menus", init_menus)
    monkeypatch.setattr(init_app, "init_apis", init_apis)
    monkeypatch.setattr(init_app, "init_roles", init_roles)
    monkeypatch.setattr(
        init_app,
        "sync_business_ledger_admin_entries",
        sync_business_ledger_admin_entries,
        raising=False,
    )

    await init_app.init_data()

    init_db.assert_awaited_once_with(run_migrations=False)
    sync_business_ledger_admin_entries.assert_awaited_once()
    init_superuser.assert_not_awaited()
    init_menus.assert_not_awaited()
    init_apis.assert_not_awaited()
    init_roles.assert_not_awaited()
