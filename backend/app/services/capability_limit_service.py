from dataclasses import dataclass

from app.models import AppUser, SystemConfig
from app.utils.parse import safe_parse_bool

CERTIFICATION_MALE_ONLY_KEY = "capability_certification_male_only_enabled"
CERTIFICATION_FEMALE_ONLY_KEY = "capability_certification_female_only_enabled"
PROFILE_EDIT_CERTIFIED_ONLY_KEY = "capability_profile_edit_certified_only_enabled"
MOMENT_PUBLISH_CERTIFIED_ONLY_KEY = "capability_moment_publish_certified_only_enabled"

CERTIFICATION_CLOSED_MESSAGE = "当前暂未开放真人认证申请"
CERTIFICATION_MALE_ONLY_MESSAGE = "当前仅开放男性用户申请真人认证"
CERTIFICATION_FEMALE_ONLY_MESSAGE = "当前仅开放女性用户申请真人认证"
PROFILE_EDIT_CERTIFIED_ONLY_MESSAGE = "通过真人认证后才可以编辑资料"
MOMENT_PUBLISH_CERTIFIED_ONLY_MESSAGE = "通过真人认证后才可以发布动态"


@dataclass(frozen=True)
class CapabilityLimitConfig:
    certification_male_only_enabled: bool = False
    certification_female_only_enabled: bool = False
    profile_edit_certified_only_enabled: bool = False
    moment_publish_certified_only_enabled: bool = False

    def dump(self) -> dict:
        return {
            "certification_male_only_enabled": self.certification_male_only_enabled,
            "certification_female_only_enabled": self.certification_female_only_enabled,
            "profile_edit_certified_only_enabled": self.profile_edit_certified_only_enabled,
            "moment_publish_certified_only_enabled": self.moment_publish_certified_only_enabled,
        }


def parse_capability_limit_config(config_map: dict[str, str]) -> CapabilityLimitConfig:
    return CapabilityLimitConfig(
        certification_male_only_enabled=safe_parse_bool(
            config_map.get(CERTIFICATION_MALE_ONLY_KEY),
            False,
        ),
        certification_female_only_enabled=safe_parse_bool(
            config_map.get(CERTIFICATION_FEMALE_ONLY_KEY),
            False,
        ),
        profile_edit_certified_only_enabled=safe_parse_bool(
            config_map.get(PROFILE_EDIT_CERTIFIED_ONLY_KEY),
            False,
        ),
        moment_publish_certified_only_enabled=safe_parse_bool(
            config_map.get(MOMENT_PUBLISH_CERTIFIED_ONLY_KEY),
            False,
        ),
    )


async def load_capability_limit_config() -> CapabilityLimitConfig:
    try:
        config_map = await SystemConfig.get_all_as_dict()
    except Exception:  # noqa: BLE001
        return CapabilityLimitConfig()
    return parse_capability_limit_config(config_map)


def certification_denial_message(
    user: AppUser,
    config: CapabilityLimitConfig,
) -> str | None:
    if bool(getattr(user, "is_certified_user", False)):
        return None

    male_only = config.certification_male_only_enabled
    female_only = config.certification_female_only_enabled
    if male_only and female_only:
        return CERTIFICATION_CLOSED_MESSAGE

    gender = str(getattr(user, "gender", None) or "male").strip().lower()
    if male_only and gender != "male":
        return CERTIFICATION_MALE_ONLY_MESSAGE
    if female_only and gender != "female":
        return CERTIFICATION_FEMALE_ONLY_MESSAGE
    return None


def moment_publish_denial_message(
    user: AppUser,
    config: CapabilityLimitConfig,
) -> str | None:
    if config.moment_publish_certified_only_enabled and not bool(
        getattr(user, "is_certified_user", False),
    ):
        return MOMENT_PUBLISH_CERTIFIED_ONLY_MESSAGE
    return None


def profile_edit_denial_message(
    user: AppUser,
    config: CapabilityLimitConfig,
) -> str | None:
    if config.profile_edit_certified_only_enabled and not bool(
        getattr(user, "is_certified_user", False),
    ):
        return PROFILE_EDIT_CERTIFIED_ONLY_MESSAGE
    return None
