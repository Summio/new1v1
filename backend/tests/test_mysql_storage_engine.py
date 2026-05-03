import importlib.util
import asyncio
from pathlib import Path
import sys

BACKEND_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_ROOT))

from app.settings import TORTOISE_ORM  # noqa: E402


def test_tortoise_mysql_connection_uses_innodb_storage_engine():
    credentials = TORTOISE_ORM["connections"]["mysql"]["credentials"]

    assert credentials["storage_engine"] == "InnoDB"
    assert credentials["init_command"] == "SET default_storage_engine=InnoDB"


def test_innodb_migration_converts_existing_myisam_tables():
    migration_path = BACKEND_ROOT / "migrations" / "models" / "18_20260503120000_convert_mysql_tables_to_innodb.py"
    spec = importlib.util.spec_from_file_location("convert_mysql_tables_to_innodb", migration_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)

    sql = asyncio.run(module.upgrade(None))
    expected_tables = {
        "aerich",
        "api",
        "app_user",
        "auditlog",
        "call_record",
        "dept",
        "deptclosure",
        "gift",
        "gift_record",
        "menu",
        "moment_media",
        "moments",
        "recharge_order",
        "role",
        "role_api",
        "role_menu",
        "system_config",
        "user",
        "user_role",
        "withdraw_apply",
    }

    for table in expected_tables:
        assert f"ALTER TABLE `{table}` ENGINE=InnoDB;" in sql
