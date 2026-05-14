from dataclasses import dataclass

from app.models import AppUser, SystemConfig
from app.utils.parse import safe_parse_int

DEFAULT_CUSTOMER_SERVICE_NICKNAME = "在线客服"
CUSTOMER_SERVICE_INTERACTION_BLOCK_MESSAGE = "客服账号仅支持在线客服会话"


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


async def get_customer_service_user_id(config_map: dict[str, str] | None = None) -> int | None:
    customer_service = await load_customer_service_config(config_map)
    if not customer_service.enabled or customer_service.user_id is None:
        return None
    return int(customer_service.user_id)


async def is_customer_service_user_id(
    user_id: int | str | None,
    config_map: dict[str, str] | None = None,
) -> bool:
    try:
        normalized_user_id = int(user_id or 0)
    except (TypeError, ValueError):
        return False
    if normalized_user_id <= 0:
        return False
    customer_service_user_id = await get_customer_service_user_id(config_map)
    return customer_service_user_id is not None and normalized_user_id == customer_service_user_id


async def filter_customer_service_user_ids(user_ids):
    customer_service_user_id = await get_customer_service_user_id()
    if customer_service_user_id is None:
        return list(user_ids)
    return [user_id for user_id in user_ids if int(user_id) != customer_service_user_id]


async def exclude_customer_service_user(query, config_map: dict[str, str] | None = None):
    customer_service_user_id = await get_customer_service_user_id(config_map)
    if customer_service_user_id is None:
        return query
    return query.exclude(id=customer_service_user_id)
