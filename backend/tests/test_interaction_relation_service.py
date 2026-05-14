from types import SimpleNamespace

import pytest

from app.services import interaction_relation_service as service
from app.services.interaction_relation_service import (
    InteractionRelationConfig,
    InteractionRelationError,
    InteractionRelationRuntime,
    ensure_interaction_allowed,
    parse_interaction_relation_config,
)


def _user(
    *,
    user_id: int = 1,
    gender: str | None = "male",
    is_certified_user: bool = False,
) -> SimpleNamespace:
    return SimpleNamespace(
        id=user_id,
        gender=gender,
        is_certified_user=is_certified_user,
    )


async def _install_runtime(
    monkeypatch: pytest.MonkeyPatch,
    config: InteractionRelationConfig,
    *,
    customer_service_user_id: int | None = None,
) -> None:
    async def fake_load_runtime() -> InteractionRelationRuntime:
        return InteractionRelationRuntime(
            config=config,
            customer_service_user_id=customer_service_user_id,
        )

    monkeypatch.setattr(service, "_load_interaction_relation_runtime", fake_load_runtime)


@pytest.mark.asyncio
async def test_default_config_allows_all_actions(monkeypatch: pytest.MonkeyPatch) -> None:
    await _install_runtime(monkeypatch, InteractionRelationConfig())

    await ensure_interaction_allowed(
        action="follow",
        actor=_user(user_id=1, gender="male", is_certified_user=False),
        target=_user(user_id=2, gender="male", is_certified_user=False),
    )


@pytest.mark.parametrize(
    "action, actor_gender, target_gender, actor_certified, target_certified, opp_enabled, mix_enabled, expected",
    [
        ("follow", "male", "female", False, True, True, False, True),
        ("follow", "male", "male", False, True, True, False, False),
        ("call", "male", "female", False, False, False, True, False),
        ("gift", "female", "female", False, False, False, True, False),
        ("im_text", "male", "female", False, True, True, True, True),
        ("im_text", "male", "female", False, False, True, True, False),
    ],
)
@pytest.mark.asyncio
async def test_interaction_rule_matrix(
    monkeypatch: pytest.MonkeyPatch,
    action: str,
    actor_gender: str,
    target_gender: str,
    actor_certified: bool,
    target_certified: bool,
    opp_enabled: bool,
    mix_enabled: bool,
    expected: bool,
) -> None:
    config = InteractionRelationConfig(
        **{
            f"{action}_opposite_gender_enabled": opp_enabled,
            f"{action}_certified_mix_enabled": mix_enabled,
        }
    )
    await _install_runtime(monkeypatch, config)

    call = ensure_interaction_allowed(
        action=action,  # type: ignore[arg-type]
        actor=_user(user_id=1, gender=actor_gender, is_certified_user=actor_certified),
        target=_user(user_id=2, gender=target_gender, is_certified_user=target_certified),
    )
    if expected:
        await call
    else:
        with pytest.raises(InteractionRelationError):
            await call


@pytest.mark.asyncio
async def test_customer_service_participant_allows_text_chat_only(monkeypatch: pytest.MonkeyPatch) -> None:
    await _install_runtime(
        monkeypatch,
        InteractionRelationConfig(
            follow_opposite_gender_enabled=True,
            follow_certified_mix_enabled=True,
            call_opposite_gender_enabled=True,
            call_certified_mix_enabled=True,
            gift_opposite_gender_enabled=True,
            gift_certified_mix_enabled=True,
            im_text_opposite_gender_enabled=False,
            im_text_certified_mix_enabled=False,
        ),
        customer_service_user_id=2,
    )

    await ensure_interaction_allowed(
        action="im_text",
        actor=_user(user_id=1, gender="male", is_certified_user=False),
        target=_user(user_id=2, gender="male", is_certified_user=False),
    )

    for action in ("follow", "call", "gift"):
        with pytest.raises(InteractionRelationError) as exc_info:
            await ensure_interaction_allowed(
                action=action,  # type: ignore[arg-type]
                actor=_user(user_id=1, gender="male", is_certified_user=False),
                target=_user(user_id=2, gender="male", is_certified_user=False),
            )

        assert exc_info.value.code == 403


def test_parse_interaction_relation_config_defaults_to_disabled() -> None:
    config = parse_interaction_relation_config({})

    assert config.follow_opposite_gender_enabled is False
    assert config.follow_certified_mix_enabled is False
    assert config.im_text_opposite_gender_enabled is False
    assert config.im_text_certified_mix_enabled is False
    assert config.call_opposite_gender_enabled is False
    assert config.call_certified_mix_enabled is False
    assert config.gift_opposite_gender_enabled is False
    assert config.gift_certified_mix_enabled is False


def test_parse_interaction_relation_config_reads_bool_values() -> None:
    config = parse_interaction_relation_config(
        {
            "interaction_follow_opposite_gender_enabled": "1",
            "interaction_follow_certified_mix_enabled": "true",
            "interaction_im_text_opposite_gender_enabled": "yes",
            "interaction_im_text_certified_mix_enabled": "on",
            "interaction_call_opposite_gender_enabled": "0",
            "interaction_call_certified_mix_enabled": "false",
            "interaction_gift_opposite_gender_enabled": "bad",
            "interaction_gift_certified_mix_enabled": "1",
        }
    )

    assert config.follow_opposite_gender_enabled is True
    assert config.follow_certified_mix_enabled is True
    assert config.im_text_opposite_gender_enabled is True
    assert config.im_text_certified_mix_enabled is True
    assert config.call_opposite_gender_enabled is False
    assert config.call_certified_mix_enabled is False
    assert config.gift_opposite_gender_enabled is False
    assert config.gift_certified_mix_enabled is True
