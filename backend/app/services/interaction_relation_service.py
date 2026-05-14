from dataclasses import dataclass
from typing import Literal

from app.models import AppUser, SystemConfig
from app.services.customer_service import (
    CUSTOMER_SERVICE_INTERACTION_BLOCK_MESSAGE,
    load_customer_service_config,
)
from app.utils.parse import safe_parse_bool

InteractionAction = Literal["follow", "im_text", "call", "gift"]


@dataclass(frozen=True)
class InteractionRelationConfig:
    follow_opposite_gender_enabled: bool = False
    follow_certified_mix_enabled: bool = False
    im_text_opposite_gender_enabled: bool = False
    im_text_certified_mix_enabled: bool = False
    call_opposite_gender_enabled: bool = False
    call_certified_mix_enabled: bool = False
    gift_opposite_gender_enabled: bool = False
    gift_certified_mix_enabled: bool = False


@dataclass(frozen=True)
class InteractionRelationRuntime:
    config: InteractionRelationConfig
    customer_service_user_id: int | None = None


class InteractionRelationError(Exception):
    def __init__(self, code: int, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


_ACTION_LABELS: dict[InteractionAction, str] = {
    "follow": "关注",
    "im_text": "文字聊天",
    "call": "视频通话",
    "gift": "送礼",
}


def parse_interaction_relation_config(config_map: dict[str, str]) -> InteractionRelationConfig:
    return InteractionRelationConfig(
        follow_opposite_gender_enabled=safe_parse_bool(
            config_map.get("interaction_follow_opposite_gender_enabled"),
            False,
        ),
        follow_certified_mix_enabled=safe_parse_bool(
            config_map.get("interaction_follow_certified_mix_enabled"),
            False,
        ),
        im_text_opposite_gender_enabled=safe_parse_bool(
            config_map.get("interaction_im_text_opposite_gender_enabled"),
            False,
        ),
        im_text_certified_mix_enabled=safe_parse_bool(
            config_map.get("interaction_im_text_certified_mix_enabled"),
            False,
        ),
        call_opposite_gender_enabled=safe_parse_bool(
            config_map.get("interaction_call_opposite_gender_enabled"),
            False,
        ),
        call_certified_mix_enabled=safe_parse_bool(
            config_map.get("interaction_call_certified_mix_enabled"),
            False,
        ),
        gift_opposite_gender_enabled=safe_parse_bool(
            config_map.get("interaction_gift_opposite_gender_enabled"),
            False,
        ),
        gift_certified_mix_enabled=safe_parse_bool(
            config_map.get("interaction_gift_certified_mix_enabled"),
            False,
        ),
    )


async def _load_interaction_relation_runtime() -> InteractionRelationRuntime:
    try:
        config_map = await SystemConfig.get_all_as_dict()
    except Exception:  # noqa: BLE001
        return InteractionRelationRuntime(config=InteractionRelationConfig())

    config = parse_interaction_relation_config(config_map)
    customer_service_user_id = None
    try:
        customer_service_config = await load_customer_service_config(config_map)
        if customer_service_config.enabled and customer_service_config.user_id is not None:
            customer_service_user_id = int(customer_service_config.user_id)
    except Exception:  # noqa: BLE001
        customer_service_user_id = None
    return InteractionRelationRuntime(
        config=config,
        customer_service_user_id=customer_service_user_id,
    )


def _user_id(user: AppUser) -> int:
    try:
        return int(getattr(user, "id", 0) or 0)
    except (TypeError, ValueError):
        return 0


def _gender(user: AppUser) -> str:
    value = str(getattr(user, "gender", None) or "male").strip().lower()
    return value if value in {"male", "female"} else "male"


def _is_certified(user: AppUser) -> bool:
    return bool(getattr(user, "is_certified_user", False))


def _is_customer_service_participant(
    actor: AppUser,
    target: AppUser,
    customer_service_user_id: int | None,
) -> bool:
    if customer_service_user_id is None or customer_service_user_id <= 0:
        return False
    return _user_id(actor) == customer_service_user_id or _user_id(target) == customer_service_user_id


def _is_opposite_gender(actor: AppUser, target: AppUser) -> bool:
    return _gender(actor) != _gender(target)


def _is_certified_mix(actor: AppUser, target: AppUser) -> bool:
    return _is_certified(actor) != _is_certified(target)


def _rule_flags(
    config: InteractionRelationConfig,
    action: InteractionAction,
) -> tuple[bool, bool]:
    return (
        bool(getattr(config, f"{action}_opposite_gender_enabled")),
        bool(getattr(config, f"{action}_certified_mix_enabled")),
    )


async def ensure_interaction_allowed(
    *,
    action: InteractionAction,
    actor: AppUser,
    target: AppUser,
    bypass_limits: bool = False,
) -> None:
    if bypass_limits:
        return

    runtime = await _load_interaction_relation_runtime()
    if _is_customer_service_participant(actor, target, runtime.customer_service_user_id):
        if action == "im_text":
            return
        raise InteractionRelationError(403, CUSTOMER_SERVICE_INTERACTION_BLOCK_MESSAGE)

    opposite_gender_enabled, certified_mix_enabled = _rule_flags(runtime.config, action)
    action_label = _ACTION_LABELS[action]
    if opposite_gender_enabled and not _is_opposite_gender(actor, target):
        raise InteractionRelationError(403, f"当前{action_label}仅允许异性之间")
    if certified_mix_enabled and not _is_certified_mix(actor, target):
        raise InteractionRelationError(403, f"当前{action_label}仅允许普通用户和认证用户之间")
