from pathlib import Path

from app.core import init_app


BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _menu_summary(menus):
    return {(menu.name, menu.path, menu.component) for menu in menus}


def test_operation_menu_keeps_only_daily_operation_children() -> None:
    children = init_app.build_operation_children(parent_id=100)

    assert _menu_summary(children) == {
        ("用户管理", "app-user", "/operation/app-user"),
        ("通话记录", "call-record", "/operation/call-record"),
        ("礼物管理", "gift", "/operation/gift"),
        ("动态管理", "moment", "/operation/moment"),
        ("排行榜", "ranking", "/operation/ranking"),
        ("系统通知", "system-notification", "/operation/system-notification"),
        ("投诉管理", "complaint", "/operation/complaint"),
        ("意见反馈", "feedback", "/operation/feedback"),
    }


def test_review_finance_and_settings_menu_blueprints_exist() -> None:
    assert _menu_summary(init_app.build_review_children(parent_id=200)) == {
        ("真人认证审核", "certification-review", "/operation/certification-review"),
        ("资料编辑审核", "profile-review", "/operation/profile-review"),
        ("提现账户审核", "withdraw-account", "/operation/withdraw-account"),
    }
    assert _menu_summary(init_app.build_finance_children(parent_id=300)) == {
        ("充值管理", "recharge", "/operation/recharge"),
        ("提现管理", "withdraw", "/operation/withdraw"),
        ("手续费账单", "fee-bill", "/operation/fee-bill"),
        ("全量业务流水", "business-ledger", "/operation/business-ledger"),
        ("代币修改记录", "token-adjust-record", "/operation/token-adjust-record"),
    }
    assert _menu_summary(init_app.build_settings_children(parent_id=400)) == {
        ("充值配置", "recharge-config", "/system/recharge-config"),
        ("提现配置", "withdraw-config", "/system/withdraw-config"),
        ("初始资料管理", "initial-profile", "/system/initial-profile"),
    }


def test_startup_menu_seed_uses_accepted_top_level_categories() -> None:
    init_app_src = (BACKEND_ROOT / "app/core/init_app.py").read_text(encoding="utf-8")

    for expected in [
        'name="运营"',
        'path="/operation"',
        'redirect="/operation/app-user"',
        'name="审核"',
        'path="/review"',
        'redirect="/review/certification-review"',
        'name="财务"',
        'path="/finance"',
        'redirect="/finance/recharge"',
        'name="设置"',
        'path="/settings"',
        'redirect="/settings/recharge-config"',
    ]:
        assert expected in init_app_src

    assert 'name="运营中心"' not in init_app_src
    assert 'await _ensure_menu_exists(\n        name="一级菜单"' not in init_app_src
    assert "hide_legacy_top_menu" in init_app_src
    assert "sync_role_parent_menu_permissions" in init_app_src
