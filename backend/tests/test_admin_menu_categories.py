from pathlib import Path

from app.core import init_app


BACKEND_ROOT = Path(__file__).resolve().parents[1]


def _menu_summary(menus):
    return {(menu.name, menu.path, menu.component) for menu in menus}


def _menu_icons(menus):
    return {menu.name: menu.icon for menu in menus}


def _menu_orders(menus):
    return {menu.name: menu.order for menu in menus}


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
        ("常用语审核", "common-phrase-review", "/operation/common-phrase-review"),
    }
    assert _menu_summary(init_app.build_finance_children(parent_id=300)) == {
        ("充值管理", "recharge", "/operation/recharge"),
        ("代币流水", "business-ledger", "/operation/business-ledger"),
        ("提现管理", "withdraw", "/operation/withdraw"),
        ("手续费账单", "fee-bill", "/operation/fee-bill"),
        ("代币修改记录", "token-adjust-record", "/operation/token-adjust-record"),
    }
    assert _menu_orders(init_app.build_finance_children(parent_id=300))["代币流水"] == 2
    assert _menu_summary(init_app.build_settings_children(parent_id=400)) == {
        ("充值配置", "recharge-config", "/system/recharge-config"),
        ("提现配置", "withdraw-config", "/system/withdraw-config"),
        ("初始资料管理", "initial-profile", "/system/initial-profile"),
        ("搭讪配置", "flirt-config", "/system/flirt-config"),
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


def test_admin_menu_icons_match_menu_purpose() -> None:
    assert _menu_icons(init_app.build_operation_children(parent_id=100)) == {
        "用户管理": "material-symbols:group-outline-rounded",
        "通话记录": "material-symbols:call-log-outline-rounded",
        "礼物管理": "material-symbols:featured-seasonal-and-gifts-rounded",
        "动态管理": "material-symbols:dynamic-feed-rounded",
        "排行榜": "material-symbols:leaderboard-outline-rounded",
        "系统通知": "material-symbols:notifications-outline-rounded",
        "投诉管理": "material-symbols:report-outline-rounded",
        "意见反馈": "material-symbols:feedback-outline-rounded",
    }
    assert _menu_icons(init_app.build_review_children(parent_id=200)) == {
        "真人认证审核": "material-symbols:verified-user-outline-rounded",
        "资料编辑审核": "material-symbols:manage-accounts-outline-rounded",
        "提现账户审核": "material-symbols:account-balance-outline-rounded",
        "常用语审核": "material-symbols:chat-paste-go-outline-rounded",
    }
    assert _menu_icons(init_app.build_finance_children(parent_id=300)) == {
        "充值管理": "material-symbols:add-card-outline-rounded",
        "代币流水": "material-symbols:data-table-outline-rounded",
        "提现管理": "material-symbols:payments-outline-rounded",
        "手续费账单": "material-symbols:receipt-long-outline-rounded",
        "代币修改记录": "material-symbols:currency-exchange-rounded",
    }
    assert _menu_icons(init_app.build_settings_children(parent_id=400)) == {
        "充值配置": "material-symbols:price-change-outline-rounded",
        "提现配置": "material-symbols:request-quote-outline-rounded",
        "初始资料管理": "material-symbols:badge-outline-rounded",
        "搭讪配置": "material-symbols:forum-outline-rounded",
    }


def test_top_level_and_system_menu_icons_match_menu_purpose() -> None:
    init_app_src = (BACKEND_ROOT / "app/core/init_app.py").read_text(encoding="utf-8")

    for expected in [
        'name="运营",\n        parent_id=0,\n        menu_type=MenuType.CATALOG,\n        path="/operation",\n        order=1,\n        icon="material-symbols:monitoring-rounded"',
        'name="审核",\n        parent_id=0,\n        menu_type=MenuType.CATALOG,\n        path="/review",\n        order=2,\n        icon="material-symbols:fact-check-outline-rounded"',
        'name="财务",\n        parent_id=0,\n        menu_type=MenuType.CATALOG,\n        path="/finance",\n        order=3,\n        icon="material-symbols:account-balance-wallet-outline-rounded"',
        'name="设置",\n        parent_id=0,\n        menu_type=MenuType.CATALOG,\n        path="/settings",\n        order=4,\n        icon="material-symbols:tune-rounded"',
        'name="系统管理",\n        parent_id=0,\n        menu_type=MenuType.CATALOG,\n        path="/system",\n        order=5,\n        icon="material-symbols:admin-panel-settings-outline-rounded"',
        '"name": "用户管理",\n            "path": "user",\n            "order": 1,\n            "icon": "material-symbols:person-outline-rounded"',
        '"name": "角色管理",\n            "path": "role",\n            "order": 2,\n            "icon": "material-symbols:assignment-ind-outline"',
        '"name": "菜单管理",\n            "path": "menu",\n            "order": 3,\n            "icon": "material-symbols:lists-rounded"',
        '"name": "API管理",\n            "path": "api",\n            "order": 4,\n            "icon": "material-symbols:api-rounded"',
        '"name": "部门管理",\n            "path": "dept",\n            "order": 5,\n            "icon": "material-symbols:account-tree-outline-rounded"',
        '"name": "审计日志",\n            "path": "auditlog",\n            "order": 6,\n            "icon": "material-symbols:plagiarism-outline-rounded"',
        '"name": "系统配置",\n            "path": "config",\n            "order": 7,\n            "icon": "material-symbols:settings-outline-rounded"',
    ]:
        assert expected in init_app_src
