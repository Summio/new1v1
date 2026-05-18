import json
import uuid
from datetime import datetime, timedelta

from tortoise.transactions import in_transaction

from app.core.time_utils import now_local_naive, to_local_naive_for_db
from app.models import AppUser, SystemConfig, VipOrder
from app.schemas.system import VipPackageItem

VIP_PACKAGES_KEY = "vip_packages"
DEFAULT_VIP_PACKAGES = [
    {"amount": 1990, "duration_days": 30, "label": "月卡", "tag": "推荐", "tag_color": "#D7A84F"},
    {"amount": 5800, "duration_days": 90, "label": "季卡", "tag": "省心", "tag_color": "#C7902D"},
    {"amount": 19800, "duration_days": 365, "label": "年卡", "tag": "超值", "tag_color": "#B7791F"},
]


def dump_vip_package(item: VipPackageItem) -> dict[str, str | int | None]:
    return item.model_dump(mode="json")


def parse_vip_packages(raw_value: str | None) -> list[VipPackageItem]:
    try:
        data = json.loads(raw_value or "[]")
    except (json.JSONDecodeError, ValueError, TypeError):
        return []
    if not isinstance(data, list):
        return []
    packages: list[VipPackageItem] = []
    for item in data:
        if not isinstance(item, dict):
            continue
        try:
            packages.append(VipPackageItem(**item))
        except Exception:  # noqa: BLE001
            continue
    return packages


async def load_vip_packages(config_map: dict[str, str] | None = None) -> list[VipPackageItem]:
    if config_map is None:
        raw_value = await SystemConfig.get_value(VIP_PACKAGES_KEY, "[]")
    else:
        raw_value = config_map.get(VIP_PACKAGES_KEY, "[]")
    return parse_vip_packages(raw_value)


def normalize_vip_datetime(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return to_local_naive_for_db(value)


def is_user_vip(user: AppUser | None, *, now: datetime | None = None) -> bool:
    if user is None:
        return False
    expires_at = normalize_vip_datetime(getattr(user, "vip_expires_at", None))
    if expires_at is None:
        return False
    current = normalize_vip_datetime(now) if now else now_local_naive()
    return expires_at > current


def vip_payload(user: AppUser | None, *, now: datetime | None = None) -> dict[str, object]:
    expires_at = normalize_vip_datetime(getattr(user, "vip_expires_at", None) if user is not None else None)
    return {
        "is_vip": is_user_vip(user, now=now),
        "vip_expires_at": expires_at.isoformat() if expires_at else None,
    }


def resolve_next_vip_expires_at(
    *,
    current_expires_at: datetime | None,
    duration_days: int,
    now: datetime | None = None,
) -> datetime:
    current = normalize_vip_datetime(now) if now else now_local_naive()
    expires_at = normalize_vip_datetime(current_expires_at)
    base = expires_at if expires_at and expires_at > current else current
    return base + timedelta(days=int(duration_days))


def create_vip_order_no(*, now: datetime | None = None, random_hex: str | None = None) -> str:
    current = normalize_vip_datetime(now) if now else now_local_naive()
    suffix = (random_hex or uuid.uuid4().hex[:8]).upper()
    return f"V{current.strftime('%Y%m%d%H%M%S')}{suffix}"


async def create_vip_order(*, user_id: int, package_index: int, pay_channel: str) -> VipOrder:
    if pay_channel not in {"wx", "alipay"}:
        raise ValueError("支付渠道仅支持 wx/alipay")
    packages = await load_vip_packages()
    if package_index < 0 or package_index >= len(packages):
        raise ValueError("VIP套餐不存在")
    package = packages[package_index]
    order_no = None
    for _ in range(3):
        candidate = create_vip_order_no()
        if not await VipOrder.filter(order_no=candidate).exists():
            order_no = candidate
            break
    if not order_no:
        raise RuntimeError("订单创建失败，请重试")
    return await VipOrder.create(
        user_id=user_id,
        order_no=order_no,
        amount=package.amount,
        duration_days=int(package.duration_days),
        package_snapshot=dump_vip_package(package),
        status="pending",
        pay_channel=pay_channel,
    )


async def mark_vip_order_paid(order_no: str, *, user_id: int | None = None) -> VipOrder:
    async with in_transaction() as conn:
        query = VipOrder.filter(order_no=order_no, status="pending")
        if user_id is not None:
            query = query.filter(user_id=user_id)
        order = await query.using_db(conn).select_for_update().first()
        if not order:
            raise ValueError("订单不存在或已处理")
        user = await AppUser.filter(id=order.user_id).using_db(conn).select_for_update().first()
        if not user:
            raise ValueError("用户不存在")
        before = user.vip_expires_at
        after = resolve_next_vip_expires_at(
            current_expires_at=before,
            duration_days=int(order.duration_days),
            now=now_local_naive(),
        )
        await AppUser.filter(id=user.id).using_db(conn).update(vip_expires_at=after)
        order.status = "paid"
        order.paid_at = now_local_naive()
        order.before_vip_expires_at = before
        order.after_vip_expires_at = after
        await order.save(
            using_db=conn,
            update_fields=[
                "status",
                "paid_at",
                "before_vip_expires_at",
                "after_vip_expires_at",
            ],
        )
    return order
