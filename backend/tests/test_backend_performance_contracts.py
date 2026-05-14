import inspect
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.api.v1.app import call, certified_user  # noqa: E402
from app.core import init_app  # noqa: E402
from app.websocket import presence  # noqa: E402

CERTIFIED_USER_API = BACKEND_ROOT / "app/api/v1/app/certified_user.py"
PRESENCE = BACKEND_ROOT / "app/websocket/presence.py"
INIT_APP = BACKEND_ROOT / "app/core/init_app.py"
CALL_API = BACKEND_ROOT / "app/api/v1/app/call.py"
MIGRATIONS_DIR = BACKEND_ROOT / "migrations/models"


def test_certified_user_list_uses_bounded_online_page_helpers() -> None:
    presence_text = PRESENCE.read_text(encoding="utf-8")
    source = inspect.getsource(certified_user.certified_user_list)
    fetch_source = inspect.getsource(certified_user._fetch_sorted_certified_user_page)
    page_helper_source = inspect.getsource(presence.get_online_user_id_page)
    batch_helper_source = inspect.getsource(presence.filter_online_user_ids)

    assert "get_online_user_ids" not in source
    assert "get_online_since_map" not in source
    assert "get_online_user_id_page" in fetch_source
    assert "count_online_user_ids" in fetch_source
    assert "filter_online_user_ids" in fetch_source
    assert "smembers(_WS_ONLINE_KEY)" not in page_helper_source
    assert "zrange(_WS_ONLINE_SINCE_KEY, 0, -1" not in page_helper_source
    assert "smembers(_WS_ONLINE_KEY)" not in batch_helper_source
    assert "get_online_user_id_page" in presence_text
    assert "count_online_user_ids" in presence_text
    assert "filter_online_user_ids" in presence_text


def test_audit_log_excludes_app_business_routes() -> None:
    source = inspect.getsource(init_app.make_middlewares)

    assert '"/api/v1/app/"' in source


def test_call_trace_is_not_awaited_inside_call_state_transactions() -> None:
    call_text = CALL_API.read_text(encoding="utf-8")
    for func in [call.accept_call, call.reject_call, call.cancel_call, call.call_end]:
        source = inspect.getsource(func)
        transaction_prefix = source.split("async with in_transaction()", 1)[1]
        transaction_body = transaction_prefix.split("return Success", 1)[0]
        assert "await _append_call_trace" not in transaction_body

    assert "_schedule_call_trace" in call_text


def test_hot_path_composite_index_migration_exists() -> None:
    migration_text = "\n".join(path.read_text(encoding="utf-8") for path in sorted(MIGRATIONS_DIR.glob("*.py")))

    assert "idx_app_user_anchor_rec_perf" in migration_text
    assert "idx_call_record_caller_status_updated" in migration_text
    assert "idx_call_record_callee_status_updated" in migration_text
    assert "idx_moments_user_created_id" in migration_text
    assert "idx_moment_media_moment_sort" in migration_text
    assert "idx_recharge_user_status_created" in migration_text
    assert "idx_withdraw_user_status_created" in migration_text
    assert "idx_gift_record_sender_created" in migration_text
    assert "idx_gift_record_receiver_created" in migration_text
    assert "idx_im_text_sender_status_created" in migration_text
    assert "idx_im_text_receiver_status_created" in migration_text


def test_app_startup_initializes_db_connection_without_seed_data() -> None:
    app_init_text = (BACKEND_ROOT / "app/__init__.py").read_text(encoding="utf-8")

    assert "init_data" not in app_init_text
    assert "init_db(run_migrations=False)" in app_init_text


@pytest.mark.asyncio
async def test_startup_init_data_does_not_run_migrations_or_seed_data_by_default(monkeypatch) -> None:
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
    monkeypatch.setattr(init_app, "sync_business_ledger_admin_entries", sync_business_ledger_admin_entries)

    await init_app.init_data()

    init_db.assert_awaited_once_with(run_migrations=False)
    sync_business_ledger_admin_entries.assert_awaited_once()
    init_superuser.assert_not_awaited()
    init_menus.assert_not_awaited()
    init_apis.assert_not_awaited()
    init_roles.assert_not_awaited()


@pytest.mark.asyncio
async def test_init_db_without_startup_migrations_only_initializes_tortoise(monkeypatch) -> None:
    tortoise = SimpleNamespace(init=AsyncMock())
    monkeypatch.setattr(init_app, "Tortoise", tortoise, raising=False)
    monkeypatch.setattr(
        init_app,
        "Command",
        lambda *args, **kwargs: pytest.fail("Aerich must not run when startup migrations are disabled"),
    )

    await init_app.init_db(run_migrations=False)

    tortoise.init.assert_awaited_once_with(config=init_app.settings.TORTOISE_ORM)
