import pytest
from pydantic import ValidationError

import importlib.util
from pathlib import Path

_MODULE_PATH = Path(__file__).resolve().parents[1] / "app" / "schemas" / "app_user.py"
_SPEC = importlib.util.spec_from_file_location("app_user_schema", _MODULE_PATH)
assert _SPEC is not None and _SPEC.loader is not None
_APP_USER_SCHEMA = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_APP_USER_SCHEMA)

AnchorApplyIn = _APP_USER_SCHEMA.AnchorApplyIn
AnchorApplyReviewIn = _APP_USER_SCHEMA.AnchorApplyReviewIn


def test_anchor_apply_in_requires_face_photo_url() -> None:
    payload = AnchorApplyIn(face_photo_url="/uploads/profile/1/anchor_apply/face.jpg")
    assert payload.face_photo_url == "/uploads/profile/1/anchor_apply/face.jpg"


def test_anchor_apply_in_rejects_missing_face_photo_url() -> None:
    with pytest.raises(ValidationError):
        AnchorApplyIn()


def test_anchor_apply_review_reject_requires_reason_in_route_logic() -> None:
    payload = AnchorApplyReviewIn(id=1, status="rejected", reject_reason="")
    assert payload.status == "rejected"
    assert payload.reject_reason == ""
