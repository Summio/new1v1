import pytest
from pydantic import ValidationError

import importlib.util
from pathlib import Path

_MODULE_PATH = Path(__file__).resolve().parents[1] / "app" / "schemas" / "app_user.py"
_SPEC = importlib.util.spec_from_file_location("app_user_schema", _MODULE_PATH)
assert _SPEC is not None and _SPEC.loader is not None
_APP_USER_SCHEMA = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_APP_USER_SCHEMA)

CertificationApplyIn = _APP_USER_SCHEMA.CertificationApplyIn
CertificationReviewIn = _APP_USER_SCHEMA.CertificationReviewIn


def test_certification_apply_in_requires_face_photo_url() -> None:
    payload = CertificationApplyIn(face_photo_url="/uploads/profile/1/certification/face.jpg")
    assert payload.face_photo_url == "/uploads/profile/1/certification/face.jpg"


def test_certification_apply_in_rejects_missing_face_photo_url() -> None:
    with pytest.raises(ValidationError):
        CertificationApplyIn()


def test_certification_review_reject_requires_reason_in_route_logic() -> None:
    payload = CertificationReviewIn(id=1, status="rejected", reject_reason="")
    assert payload.status == "rejected"
    assert payload.reject_reason == ""
