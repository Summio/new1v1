from pathlib import Path

MIGRATION = Path("migrations/models/30_20260508100000_admin_moment_management_menu.py")


def test_admin_moment_menu_migration_exists() -> None:
    text = MIGRATION.read_text(encoding="utf-8")
    assert "INSERT INTO `menu`" in text
    assert "动态管理" in text
    assert "/operation/moment" in text
    assert "INSERT IGNORE INTO `role_menu`" in text
    assert "INSERT IGNORE INTO `role_api`" in text
    assert "/api/v1/moment/list" in text
    assert "/api/v1/moment/delete" in text


def test_admin_moment_menu_migration_is_reversible() -> None:
    text = MIGRATION.read_text(encoding="utf-8")
    assert "DELETE FROM `role_menu`" in text
    assert "DELETE FROM `role_api`" in text
    assert "DELETE FROM `menu`" in text
