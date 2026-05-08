from pathlib import Path

APP_USER_API = Path("app/api/v1/app/user.py")
ADMIN_USER_API = Path("app/api/v1/app_users/app_users.py")


def test_app_profile_repairs_cover_when_album_changes() -> None:
    text = APP_USER_API.read_text(encoding="utf-8")

    assert "elif req_in.album_photos is not None" in text
    assert "current_cover" in text
    assert 'update_data["cover_url"] = current_cover' in text
    assert 'update_data["cover_url"] = target_album[0] if target_album else None' in text


def test_admin_profile_repairs_cover_when_album_changes() -> None:
    text = ADMIN_USER_API.read_text(encoding="utf-8")

    assert "elif req_in.album_photos is not None" in text
    assert "current_cover" in text
    assert 'update_data["cover_url"] = current_cover' in text
    assert 'update_data["cover_url"] = target_album[0] if target_album else None' in text
