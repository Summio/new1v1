import inspect
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.api.v1.app import certified_user, moment, user  # noqa: E402
from app.api.v1.app.flirt import _build_flirt_user_query  # noqa: E402
from app.services import customer_service, interaction_relation_service  # noqa: E402
from app.services.interaction_relation_service import (  # noqa: E402
    InteractionRelationError,
)


def _read_backend_file(relative_path: str) -> str:
    return (BACKEND_ROOT / relative_path).read_text(encoding="utf-8")


def test_customer_service_helpers_define_protection_contract() -> None:
    source = inspect.getsource(customer_service)

    assert "CUSTOMER_SERVICE_INTERACTION_BLOCK_MESSAGE" in source
    assert "客服账号仅支持在线客服会话" in source
    assert "async def get_customer_service_user_id" in source
    assert "async def is_customer_service_user_id" in source
    assert "async def exclude_customer_service_user" in source


@pytest.mark.asyncio
async def test_interaction_relation_blocks_customer_service_business_actions(monkeypatch: pytest.MonkeyPatch) -> None:
    actor = SimpleNamespace(id=10, gender="male", is_certified_user=False)
    target = SimpleNamespace(id=99, gender="female", is_certified_user=True)
    runtime = interaction_relation_service.InteractionRelationRuntime(
        config=interaction_relation_service.InteractionRelationConfig(),
        customer_service_user_id=99,
    )
    monkeypatch.setattr(
        interaction_relation_service,
        "_load_interaction_relation_runtime",
        AsyncMock(return_value=runtime),
    )

    for action in ("follow", "call", "gift"):
        with pytest.raises(InteractionRelationError) as exc:
            await interaction_relation_service.ensure_interaction_allowed(
                action=action,
                actor=actor,
                target=target,
            )
        assert exc.value.code == 403
        assert exc.value.message == customer_service.CUSTOMER_SERVICE_INTERACTION_BLOCK_MESSAGE


@pytest.mark.asyncio
async def test_interaction_relation_allows_customer_service_text_chat(monkeypatch: pytest.MonkeyPatch) -> None:
    actor = SimpleNamespace(id=10, gender="male", is_certified_user=False)
    target = SimpleNamespace(id=99, gender="female", is_certified_user=True)
    runtime = interaction_relation_service.InteractionRelationRuntime(
        config=interaction_relation_service.InteractionRelationConfig(
            im_text_opposite_gender_enabled=True,
            im_text_certified_mix_enabled=True,
        ),
        customer_service_user_id=99,
    )
    monkeypatch.setattr(
        interaction_relation_service,
        "_load_interaction_relation_runtime",
        AsyncMock(return_value=runtime),
    )

    await interaction_relation_service.ensure_interaction_allowed(
        action="im_text",
        actor=actor,
        target=target,
    )


def test_customer_service_is_excluded_from_certified_user_list() -> None:
    source = inspect.getsource(certified_user.certified_user_list)

    assert "exclude_customer_service_user" in source
    assert "q = await exclude_customer_service_user(q)" in source


def test_customer_service_is_excluded_from_flirt_candidates() -> None:
    source = inspect.getsource(_build_flirt_user_query)

    assert "exclude_customer_service_user" in source
    assert "q = await exclude_customer_service_user(q)" in source


def test_customer_service_is_excluded_from_moment_surfaces() -> None:
    feed_source = inspect.getsource(moment.get_moment_feed)
    user_source = inspect.getsource(moment.get_user_moments)

    assert "customer_service_user_id = await get_customer_service_user_id()" in feed_source
    assert "query = query.exclude(user_id=customer_service_user_id)" in feed_source
    assert "await is_customer_service_user_id(user_id)" in user_source
    assert "return SuccessExtra(rows=[], total=0, has_more=False)" in user_source


def test_customer_service_is_excluded_from_app_ranking() -> None:
    source = _read_backend_file("app/services/ranking_service.py")

    assert "get_customer_service_user_id" in source
    assert "customer_service_user_id" in source
    assert 'if customer_service_user_id and int(row.get("user_id") or 0) == customer_service_user_id' in source


def test_customer_service_public_profile_and_relation_entries_are_guarded() -> None:
    public_source = inspect.getsource(user.get_user_public_profile)
    follow_status_source = inspect.getsource(user.get_user_follow_status)
    follow_source = inspect.getsource(user.follow_user)
    block_source = inspect.getsource(user.block_user)
    following_source = inspect.getsource(user.list_user_following)
    fans_source = inspect.getsource(user.list_user_fans)

    assert "scene_value = scene.strip().lower()" in public_source
    assert "await is_customer_service_user_id(user_id)" in public_source
    assert 'scene_value != "chat"' in public_source
    assert 'return Fail(code=404, msg="用户不存在")' in public_source
    assert "await is_customer_service_user_id(user_id)" in follow_status_source
    assert "is_following=False" in follow_status_source
    assert "CUSTOMER_SERVICE_INTERACTION_BLOCK_MESSAGE" in follow_source
    assert "CUSTOMER_SERVICE_INTERACTION_BLOCK_MESSAGE" in block_source
    assert "following_ids = await filter_customer_service_user_ids(following_ids)" in following_source
    assert "fan_ids = await filter_customer_service_user_ids(fan_ids)" in fans_source
