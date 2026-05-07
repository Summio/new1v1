from dataclasses import dataclass

from tortoise.expressions import F
from tortoise.transactions import in_transaction

from app.models import AppUser, ImTextMessageChargeRecord, SystemConfig
from app.schemas.system import IMTextBillingConfigOut
from app.utils.parse import clamp_int, safe_parse_int

DEFAULT_IM_TEXT_PRICE = 0
DEFAULT_IM_TEXT_ANCHOR_SHARE_BPS = 5000
MAX_ANCHOR_SHARE_BPS = 10000


@dataclass(frozen=True)
class IMTextBillingConfig:
    enabled: bool
    price: int
    anchor_share_bps: int


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
            config_map.get("im_text_message_anchor_share_bps"),
            DEFAULT_IM_TEXT_ANCHOR_SHARE_BPS,
        ),
        0,
        MAX_ANCHOR_SHARE_BPS,
    )
    return IMTextBillingConfig(enabled=enabled, price=price, anchor_share_bps=share)


def dump_im_text_billing_config(config: IMTextBillingConfig) -> dict[str, int | bool]:
    return IMTextBillingConfigOut(
        enabled=config.enabled,
        price=config.price,
        anchor_share_bps=config.anchor_share_bps,
    ).model_dump()


@dataclass(frozen=True)
class IMTextChargeResult:
    charged: bool
    price: int
    anchor_income_diamonds: int
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

    existing = await ImTextMessageChargeRecord.filter(
        sender_id=sender_id,
        request_id=request_id,
    ).first()
    if existing:
        current = await AppUser.filter(id=sender_id).first()
        return IMTextChargeResult(
            charged=True,
            price=int(existing.price),
            anchor_income_diamonds=int(existing.anchor_income_diamonds),
            coins=int(current.coins if current else sender.coins),
            diamonds=int(current.diamonds if current else sender.diamonds),
            receiver_user_id=receiver_user_id,
            request_id=request_id,
        )

    config = await load_im_text_billing_config()
    should_charge = config.enabled and config.price > 0 and bool(receiver.is_anchor) and not bool(sender.is_anchor)
    if not should_charge:
        return IMTextChargeResult(
            charged=False,
            price=0,
            anchor_income_diamonds=0,
            coins=int(sender.coins),
            diamonds=int(sender.diamonds),
            receiver_user_id=receiver_user_id,
            request_id=request_id,
        )

    price = int(config.price)
    anchor_income_diamonds = price * int(config.anchor_share_bps) // MAX_ANCHOR_SHARE_BPS
    async with in_transaction() as conn:
        updated = await AppUser.filter(
            id=sender_id,
            coins__gte=price,
        ).using_db(conn).update(coins=F("coins") - price)
        if updated == 0:
            raise IMTextBillingError(501, "余额不足，请先充值")
        if anchor_income_diamonds > 0:
            await AppUser.filter(id=receiver_user_id).using_db(conn).update(
                diamonds=F("diamonds") + anchor_income_diamonds
            )
        await ImTextMessageChargeRecord.create(
            sender_id=sender_id,
            receiver_id=receiver_user_id,
            request_id=request_id,
            price=price,
            anchor_share_bps=int(config.anchor_share_bps),
            anchor_income_diamonds=anchor_income_diamonds,
            status="charged",
            using_db=conn,
        )
        current = await AppUser.filter(id=sender_id).using_db(conn).first()

    return IMTextChargeResult(
        charged=True,
        price=price,
        anchor_income_diamonds=anchor_income_diamonds,
        coins=int(current.coins if current else 0),
        diamonds=int(current.diamonds if current else 0),
        receiver_user_id=receiver_user_id,
        request_id=request_id,
    )
