import json
from datetime import datetime
from decimal import Decimal
from types import SimpleNamespace

import pytest

from app.api.v1.app import user as user_api
from app.core.ctx import CTX_APP_USER_OBJ


@pytest.mark.asyncio
async def test_get_user_info_serializes_decimal_balances() -> None:
    app_user = SimpleNamespace(
        id=1,
        phone="13800138000",
        nickname="test",
        avatar=None,
        signature="保持开心",
        gender="secret",
        birth_date=None,
        height_cm=None,
        weight_kg=None,
        location_city=None,
        album_photos=None,
        cover_url=None,
        coins=Decimal("12.30"),
        diamonds=Decimal("4.50"),
        frozen_diamonds=Decimal("1.20"),
        status="normal",
        ban_reason=None,
        is_anchor=False,
        created_at=datetime(2026, 5, 7, 10, 30, 0),
    )

    token = CTX_APP_USER_OBJ.set(app_user)
    try:
        response = await user_api.get_user_info()
    finally:
        CTX_APP_USER_OBJ.reset(token)

    payload = json.loads(response.body)

    assert payload["code"] == 200
    assert payload["data"]["coins"] == 12.3
    assert payload["data"]["diamonds"] == 4.5
    assert payload["data"]["frozen_diamonds"] == 1.2
    assert payload["data"]["signature"] == "保持开心"
