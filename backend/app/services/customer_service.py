from dataclasses import dataclass

from app.models import AppUser, SystemConfig
from app.utils.parse import safe_parse_int

DEFAULT_CUSTOMER_SERVICE_NICKNAME = "在线客服"


@dataclass(frozen=True)
class CustomerServiceConfig:
    enabled: bool
    user_id: int | None
    nickname: str
    avatar: str | None


def _disabled_customer_service_config() -> CustomerServiceConfig:
    return CustomerServiceConfig(
        enabled=False,
        user_id=None,
        nickname=DEFAULT_CUSTOMER_SERVICE_NICKNAME,
        avatar=None,
    )


async def load_customer_service_config(
    config_map: dict[str, str] | None = None,
) -> CustomerServiceConfig:
    config = config_map if config_map is not None else await SystemConfig.get_all_as_dict()
    raw_user_id = (config.get("customer_service_user_id") or "").strip()
    user_id = safe_parse_int(raw_user_id, 0)
    if user_id <= 0:
        return _disabled_customer_service_config()

    user = await AppUser.filter(id=user_id, status="normal").first()
    if not user:
        return _disabled_customer_service_config()

    nickname = (user.nickname or "").strip() or DEFAULT_CUSTOMER_SERVICE_NICKNAME
    avatar = (user.avatar or "").strip() or None
    return CustomerServiceConfig(
        enabled=True,
        user_id=int(user.id),
        nickname=nickname,
        avatar=avatar,
    )
