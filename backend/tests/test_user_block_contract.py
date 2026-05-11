import sys
from pathlib import Path

import pytest
from pydantic import ValidationError

BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO = BACKEND_ROOT.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.schemas.app_user import UserBlockIn  # noqa: E402


def _read(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def _all_migrations() -> str:
    return "\n".join(
        path.read_text(encoding="utf-8") for path in sorted((BACKEND_ROOT / "migrations/models").glob("*.py"))
    )


def test_user_block_schema_validates_target_id() -> None:
    item = UserBlockIn(target_user_id=123)
    assert item.target_user_id == 123

    with pytest.raises(ValidationError):
        UserBlockIn(target_user_id=0)


def test_user_block_model_service_and_routes_are_registered() -> None:
    model_text = _read("app/models/user_block.py")
    service_text = _read("app/services/user_block_service.py")
    model_init_text = _read("app/models/__init__.py")
    user_api_text = _read("app/api/v1/app/user.py")

    assert "class UserBlock" in model_text
    assert 'table = "user_block"' in model_text
    assert "blocker_id = fields.BigIntField" in model_text
    assert "blocked_id = fields.BigIntField" in model_text
    assert "unique_together" in model_text
    assert "from .user_block import *" in model_init_text

    assert "get_block_relation" in service_text
    assert "ensure_not_blocked" in service_text
    assert "exclude_blocked_user_ids" in service_text
    assert "你们之间已存在黑名单关系" in service_text

    assert '@router.post("/user/block"' in user_api_text
    assert '@router.delete("/user/block"' in user_api_text
    assert '@router.get("/user/block/status"' in user_api_text
    assert '@router.get("/user/block/list"' in user_api_text
    assert "不能拉黑自己" in user_api_text
    assert "UserFollow.filter" in user_api_text
    assert "blocked_by_me" in user_api_text
    assert "blocked_me" in user_api_text
    assert "interaction_blocked" in user_api_text
    assert "blocked_at" in user_api_text


def test_user_block_migration_and_interaction_guards_exist() -> None:
    migration_text = _all_migrations()
    assert "CREATE TABLE `user_block`" in migration_text
    assert "`blocker_id` BIGINT NOT NULL" in migration_text
    assert "`blocked_id` BIGINT NOT NULL" in migration_text
    assert "uniq_user_block_pair" in migration_text
    assert "/api/v1/app/user/block" in migration_text
    assert "/api/v1/app/user/block/status" in migration_text
    assert "/api/v1/app/user/block/list" in migration_text

    user_api_text = _read("app/api/v1/app/user.py")
    im_api_text = _read("app/api/v1/app/im.py")
    call_api_text = _read("app/api/v1/app/call.py")
    gift_api_text = _read("app/api/v1/app/gift.py")
    certified_user_text = _read("app/api/v1/app/certified_user.py")

    assert "ensure_not_blocked" in user_api_text
    assert "ensure_not_blocked" in im_api_text
    assert "ensure_not_blocked" in call_api_text
    assert "ensure_not_blocked" in gift_api_text
    assert "exclude_blocked_user_ids" in certified_user_text
    assert "exclude(id__in=blocked_user_ids)" in certified_user_text
