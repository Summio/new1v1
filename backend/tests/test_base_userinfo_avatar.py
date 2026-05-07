import json
from io import BytesIO
from pathlib import Path
from unittest.mock import AsyncMock

import pytest
from fastapi import UploadFile

from app.api.v1.base import base as base_api
from app.core.ctx import CTX_USER_ID
from app.models.admin import User


class _UserWithoutAvatar:
    async def to_dict(self, exclude_fields=None):
        return {"id": 1, "username": "admin"}


class _UserWithAvatar:
    avatar = "https://cdn.example.com/uploads/admin/avatar.jpg?x=1"

    async def to_dict(self, exclude_fields=None):
        return {"id": 1, "username": "admin", "avatar": self.avatar}


@pytest.mark.asyncio
async def test_get_userinfo_returns_empty_avatar_when_user_has_no_avatar_attr(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        base_api.user_controller,
        "get",
        AsyncMock(return_value=_UserWithoutAvatar()),
    )
    token = CTX_USER_ID.set(1)
    try:
        response = await base_api.get_userinfo()
    finally:
        CTX_USER_ID.reset(token)

    payload = json.loads(response.body)
    assert payload["code"] == 200
    assert payload["data"]["avatar"] == ""


def test_admin_user_model_has_nullable_avatar_field() -> None:
    field = User._meta.fields_map["avatar"]

    assert field.null is True
    assert field.max_length == 500


@pytest.mark.asyncio
async def test_get_userinfo_returns_normalized_avatar(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        base_api.user_controller,
        "get",
        AsyncMock(return_value=_UserWithAvatar()),
    )
    token = CTX_USER_ID.set(1)
    try:
        response = await base_api.get_userinfo()
    finally:
        CTX_USER_ID.reset(token)

    payload = json.loads(response.body)
    assert payload["code"] == 200
    assert payload["data"]["avatar"] == "/uploads/admin/avatar.jpg?x=1"


@pytest.mark.asyncio
async def test_update_profile_normalizes_and_saves_avatar(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class _User:
        id = 1
        username = "admin"
        email = "admin@example.com"
        avatar = ""

        def update_from_dict(self, data):
            for key, value in data.items():
                setattr(self, key, value)
            return self

        save = AsyncMock()

    user = _User()
    monkeypatch.setattr(base_api.user_controller, "get", AsyncMock(return_value=user))
    token = CTX_USER_ID.set(1)
    try:
        response = await base_api.update_user_profile(
            base_api.UserProfileUpdate(
                username="admin",
                email="admin@example.com",
                avatar="https://cdn.example.com/uploads/admin/avatar.jpg",
            )
        )
    finally:
        CTX_USER_ID.reset(token)

    payload = json.loads(response.body)
    assert payload["code"] == 200
    assert user.avatar == "/uploads/admin/avatar.jpg"
    user.save.assert_awaited_once()


def test_admin_avatar_migration_adds_and_drops_avatar_column() -> None:
    migration_dir = Path(__file__).resolve().parents[1] / "migrations" / "models"
    migration_paths = sorted(migration_dir.glob("23_*.py"))
    content = "\n".join(path.read_text(encoding="utf-8") for path in migration_paths)

    assert "INFORMATION_SCHEMA.COLUMNS" in content
    assert "COLUMN_NAME = 'avatar'" in content
    assert "ALTER TABLE `user` ADD `avatar` VARCHAR(500)" in content
    assert "ALTER TABLE `user` DROP COLUMN `avatar`" in content


@pytest.mark.asyncio
async def test_upload_user_avatar_saves_under_current_admin_directory(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    monkeypatch.setattr(base_api.settings, "BASE_DIR", str(tmp_path))
    upload = UploadFile(file=BytesIO(b"avatar-bytes"), filename="avatar.png")
    token = CTX_USER_ID.set(7)
    try:
        response = await base_api.upload_user_avatar(upload)
    finally:
        CTX_USER_ID.reset(token)

    payload = json.loads(response.body)
    url = payload["data"]["url"]
    saved_path = tmp_path / Path(*url.lstrip("/").split("/"))

    assert payload["code"] == 200
    assert url.startswith("/uploads/admin/avatar/7/")
    assert saved_path.read_bytes() == b"avatar-bytes"
