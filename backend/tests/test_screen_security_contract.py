from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read_file(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_app_bootstrap_returns_screen_security_config() -> None:
    content = read_file("app/api/v1/app/bootstrap.py")

    assert "screen_security" in content
    assert "security_android_prevent_screenshot_enabled" in content
    assert "security_ios_prevent_screenshot_enabled" in content
    assert "android_prevent_screenshot_enabled" in content
    assert "ios_prevent_screenshot_enabled" in content


def test_admin_system_config_exposes_screen_security_switches() -> None:
    content = read_file("web/src/views/system/config/index.vue")

    assert "安全配置" in content
    assert "全局防截图(安卓)" in content
    assert "security_android_prevent_screenshot_enabled" in content
    assert "全局防截图(iOS)" in content
    assert "security_ios_prevent_screenshot_enabled" in content
