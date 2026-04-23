import json
from unittest.mock import AsyncMock

import pytest

from app.api.v1.base import base as base_api
from app.core.ctx import CTX_USER_ID


class _UserWithoutAvatar:
    async def to_dict(self, exclude_fields=None):
        return {"id": 1, "username": "admin"}


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
