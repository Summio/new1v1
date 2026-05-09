from dataclasses import dataclass
from decimal import Decimal

from tortoise.expressions import F
from tortoise.transactions import in_transaction

from app.models import AppUser, ImTextMessageChargeRecord, SystemConfig
from app.schemas.system import IMTextBillingConfigOut
from app.services.customer_service import load_customer_service_config
from app.services.gift_income_service import decimal_to_float_2, quantize_decimal_2
from app.utils.parse import clamp_int, safe_parse_int

DEFAULT_IM_TEXT_PRICE = 0
DEFAULT_IM_TEXT_CERTIFIED_USER_SHARE_BPS = 5000
MAX_CERTIFIED_USER_SHARE_BPS = 10000


@dataclass(frozen=True)
class IMTextBillingConfig:
    enabled: bool
    price: int
    certified_user_share_bps: int


def calc_im_text_certified_user_income_diamonds(
    total_price: int,
    certified_user_share_bps: int,
) -> Decimal:
    amount = max(0, int(total_price or 0))
    bps = clamp_int(int(certified_user_share_bps or 0), 0, MAX_CERTIFIED_USER_SHARE_BPS)
    income = Decimal(amount) * Decimal(bps) / Decimal(MAX_CERTIFIED_USER_SHARE_BPS)
    return quantize_decimal_2(income)


def parse_bool_config(raw: str | None, default: bool = False) -> bool:
    value = (raw or "").strip().lower()
    if value in {"1", "true", "yes", "on"}:
        return True
    if value in {"0", "false", "no", "off"}:
        return False
    return default


def parse_im_text_billing_config(config_map: dict[str, str]) -> IMTextBillingConfig:
    enabled = parse_bool_config(config_map.get("im_text_message_billing_enabled"), False)
    price = clamp_int(
        safe_parse_int(config_map.get("im_text_message_price"), DEFAULT_IM_TEXT_PRICE),
        0,
        1000000,
    )
    share = clamp_int(
        safe_parse_int(
            config_map.get("im_text_message_certified_user_share_bps"),
            DEFAULT_IM_TEXT_CERTIFIED_USER_SHARE_BPS,
        ),
        0,
        MAX_CERTIFIED_USER_SHARE_BPS,
    )
    return IMTextBillingConfig(enabled=enabled, price=price, certified_user_share_bps=share)


def dump_im_text_billing_config(config: IMTextBillingConfig) -> dict[str, int | bool]:
    return IMTextBillingConfigOut(
        enabled=config.enabled,
        price=config.price,
        certified_user_share_bps=config.certified_user_share_bps,
    ).model_dump()


def should_charge_im_text_message(
    *,
    enabled: bool,
    price: int,
    sender_is_certified_user: bool,
    receiver_is_certified_user: bool,
    receiver_is_customer_service: bool = False,
) -> bool:
    return (
        bool(enabled)
        and int(price or 0) > 0
        and not bool(sender_is_certified_user)
        and not bool(receiver_is_customer_service)
    )


def should_credit_im_text_receiver(*, receiver_is_certified_user: bool) -> bool:
    return bool(receiver_is_certified_user)


@dataclass(frozen=True)
class IMTextChargeResult:
    charged: bool
    price: int
    certified_user_income_diamonds: float
    coins: int
    diamonds: int
    receiver_user_id: int
    request_id: str


class IMTextBillingError(Exception):
    def __init__(self, code: int, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


async def load_im_text_billing_config() -> IMTextBillingConfig:
    return parse_im_text_billing_config(await SystemConfig.get_all_as_dict())


async def charge_im_text_message(
    *,
    sender_id: int,
    receiver_user_id: int,
    request_id: str,
) -> IMTextChargeResult:
    if int(sender_id) == int(receiver_user_id):
        raise IMTextBillingError(400, "不能和自己聊天")

    sender = await AppUser.filter(id=sender_id, status="normal").first()
    receiver = await AppUser.filter(id=receiver_user_id, status="normal").first()
    if not sender:
        raise IMTextBillingError(401, "登录状态异常")
    if not receiver:
        raise IMTextBillingError(404, "目标用户不存在或状态异常")

    customer_service_config = await load_customer_service_config()
    receiver_is_customer_service = (
        customer_service_config.enabled
        and customer_service_config.user_id is not None
        and int(receiver_user_id) == int(customer_service_config.user_id)
    )

    existing = await ImTextMessageChargeRecord.filter(
        sender_id=sender_id,
        request_id=request_id,
    ).first()
    if existing:
        current = await AppUser.filter(id=sender_id).first()
        return IMTextChargeResult(
            charged=True,
            price=int(existing.price),
            certified_user_income_diamonds=decimal_to_float_2(existing.certified_user_income_diamonds),
            coins=int(current.coins if current else sender.coins),
            diamonds=int(current.diamonds if current else sender.diamonds),
            receiver_user_id=receiver_user_id,
            request_id=request_id,
        )

    config = await load_im_text_billing_config()
    should_charge = should_charge_im_text_message(
        enabled=config.enabled,
        price=config.price,
        sender_is_certified_user=bool(sender.is_certified_user),
        receiver_is_certified_user=bool(receiver.is_certified_user),
        receiver_is_customer_service=receiver_is_customer_service,
    )
    if not should_charge:
        return IMTextChargeResult(
            charged=False,
            price=0,
            certified_user_income_diamonds=0,
            coins=int(sender.coins),
            diamonds=int(sender.diamonds),
            receiver_user_id=receiver_user_id,
            request_id=request_id,
        )

    price = int(config.price)
    should_credit_receiver = should_credit_im_text_receiver(receiver_is_certified_user=bool(receiver.is_certified_user))
    certified_user_income_diamonds = (
        calc_im_text_certified_user_income_diamonds(price, config.certified_user_share_bps)
        if should_credit_receiver
        else calc_im_text_certified_user_income_diamonds(0, config.certified_user_share_bps)
    )
    async with in_transaction() as conn:
        updated = (
            await AppUser.filter(
                id=sender_id,
                coins__gte=price,
            )
            .using_db(conn)
            .update(coins=F("coins") - price)
        )
        if updated == 0:
            raise IMTextBillingError(501, "余额不足，请先充值")
        if certified_user_income_diamonds > 0:
            await AppUser.filter(id=receiver_user_id).using_db(conn).update(
                diamonds=F("diamonds") + certified_user_income_diamonds
            )
        await ImTextMessageChargeRecord.create(
            sender_id=sender_id,
            receiver_id=receiver_user_id,
            request_id=request_id,
            price=price,
            certified_user_share_bps=int(config.certified_user_share_bps),
            certified_user_income_diamonds=certified_user_income_diamonds,
            status="charged",
            using_db=conn,
        )
        current = await AppUser.filter(id=sender_id).using_db(conn).first()

    return IMTextChargeResult(
        charged=True,
        price=price,
        certified_user_income_diamonds=decimal_to_float_2(certified_user_income_diamonds),
        coins=int(current.coins if current else 0),
        diamonds=int(current.diamonds if current else 0),
        receiver_user_id=receiver_user_id,
        request_id=request_id,
    )
