from types import SimpleNamespace

from app.services.capability_limit_service import (
    CERTIFICATION_CLOSED_MESSAGE,
    CERTIFICATION_FEMALE_ONLY_MESSAGE,
    CERTIFICATION_MALE_ONLY_MESSAGE,
    MOMENT_PUBLISH_CERTIFIED_ONLY_MESSAGE,
    PROFILE_EDIT_CERTIFIED_ONLY_MESSAGE,
    CapabilityLimitConfig,
    certification_denial_message,
    moment_publish_denial_message,
    profile_edit_denial_message,
    parse_capability_limit_config,
)


def _user(
    *,
    gender: str = "male",
    is_certified_user: bool = False,
) -> SimpleNamespace:
    return SimpleNamespace(
        gender=gender,
        is_certified_user=is_certified_user,
    )


def test_parse_capability_limit_config_defaults_to_disabled() -> None:
    config = parse_capability_limit_config({})

    assert config.certification_male_only_enabled is False
    assert config.certification_female_only_enabled is False
    assert config.profile_edit_certified_only_enabled is False
    assert config.moment_publish_certified_only_enabled is False


def test_parse_capability_limit_config_reads_bool_values() -> None:
    config = parse_capability_limit_config(
        {
            "capability_certification_male_only_enabled": "1",
            "capability_certification_female_only_enabled": "true",
            "capability_profile_edit_certified_only_enabled": "yes",
            "capability_moment_publish_certified_only_enabled": "on",
        }
    )

    assert config.certification_male_only_enabled is True
    assert config.certification_female_only_enabled is True
    assert config.profile_edit_certified_only_enabled is True
    assert config.moment_publish_certified_only_enabled is True


def test_certification_limits_allow_matching_gender() -> None:
    assert (
        certification_denial_message(
            _user(gender="male"),
            CapabilityLimitConfig(certification_male_only_enabled=True),
        )
        is None
    )
    assert (
        certification_denial_message(
            _user(gender="female"),
            CapabilityLimitConfig(certification_female_only_enabled=True),
        )
        is None
    )


def test_certification_limits_return_friendly_denial_messages() -> None:
    assert (
        certification_denial_message(
            _user(gender="female"),
            CapabilityLimitConfig(certification_male_only_enabled=True),
        )
        == CERTIFICATION_MALE_ONLY_MESSAGE
    )
    assert (
        certification_denial_message(
            _user(gender="male"),
            CapabilityLimitConfig(certification_female_only_enabled=True),
        )
        == CERTIFICATION_FEMALE_ONLY_MESSAGE
    )
    assert (
        certification_denial_message(
            _user(gender="male"),
            CapabilityLimitConfig(
                certification_male_only_enabled=True,
                certification_female_only_enabled=True,
            ),
        )
        == CERTIFICATION_CLOSED_MESSAGE
    )


def test_certified_users_bypass_certification_entry_limits() -> None:
    assert (
        certification_denial_message(
            _user(gender="female", is_certified_user=True),
            CapabilityLimitConfig(
                certification_male_only_enabled=True,
                certification_female_only_enabled=True,
            ),
        )
        is None
    )


def test_moment_publish_limit_blocks_non_certified_users_only() -> None:
    config = CapabilityLimitConfig(moment_publish_certified_only_enabled=True)

    assert moment_publish_denial_message(_user(is_certified_user=False), config) == (
        MOMENT_PUBLISH_CERTIFIED_ONLY_MESSAGE
    )
    assert moment_publish_denial_message(_user(is_certified_user=True), config) is None


def test_profile_edit_limit_blocks_non_certified_users_only() -> None:
    config = CapabilityLimitConfig(profile_edit_certified_only_enabled=True)

    assert profile_edit_denial_message(_user(is_certified_user=False), config) == (PROFILE_EDIT_CERTIFIED_ONLY_MESSAGE)
    assert profile_edit_denial_message(_user(is_certified_user=True), config) is None
