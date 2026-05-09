import json
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.api.v1.app import user as user_api  # noqa: E402
from app.core.ctx import CTX_APP_USER_OBJ  # noqa: E402
from app.schemas.app_user import AppUserProfileUpdateIn  # noqa: E402


@pytest.mark.asyncio
async def test_update_profile_rejects_gender_change() -> None:
    app_user = SimpleNamespace(
        id=1,
        phone="13800138000",
        nickname="test",
        avatar=None,
        signature="",
        gender="male",
        birth_date=None,
        height_cm=None,
        weight_kg=None,
        location_city=None,
        album_photos=[],
        cover_url=None,
        status="normal",
        ban_reason=None,
        is_certified_user=False,
        certification_status="none",
        certified_call_price=0,
        coins=0,
        diamonds=0,
        frozen_diamonds=0,
        created_at=None,
    )

    token = CTX_APP_USER_OBJ.set(app_user)
    try:
        response = await user_api.update_user_profile(
            AppUserProfileUpdateIn(gender="female")
        )
    finally:
        CTX_APP_USER_OBJ.reset(token)

    payload = json.loads(response.body)
    assert payload["code"] == 400
    assert payload["msg"] == "性别注册后不可修改"
