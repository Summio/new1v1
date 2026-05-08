from pathlib import Path
import sys

import pytest
from pydantic import ValidationError

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.models.user_follow import UserFollow  # noqa: E402
from app.schemas.app_user import UserFollowIn  # noqa: E402


def _read_backend_file(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def test_user_follow_schema_validates_target_id() -> None:
    item = UserFollowIn(target_user_id=123)
    assert item.target_user_id == 123

    with pytest.raises(ValidationError):
        UserFollowIn(target_user_id=0)


def test_user_follow_model_exists() -> None:
    assert UserFollow.Meta.table == "user_follow"


def test_user_follow_routes_are_declared() -> None:
    content = _read_backend_file("app/api/v1/app/user.py")
    assert "/user/public" in content
    assert "/user/follow/status" in content
    assert "/user/follow" in content
    assert "/user/follow/list" in content
    assert "/user/fans/list" in content
    assert "following_id=current_user_id" in content
    assert "is_following" in content
    assert "keyword" in content
