import json

from app.models import SystemConfig

CERTIFIED_CALL_PRICE_TIERS_KEY = "certified_call_price_tiers"
DEFAULT_CERTIFIED_CALL_PRICE_TIERS = [0, 100, 200, 300, 500]


def parse_certified_call_price_tiers(raw_value: str | None) -> list[int]:
    try:
        decoded = json.loads(raw_value or "[]")
    except (TypeError, ValueError, json.JSONDecodeError):
        return DEFAULT_CERTIFIED_CALL_PRICE_TIERS.copy()
    if not isinstance(decoded, list):
        return DEFAULT_CERTIFIED_CALL_PRICE_TIERS.copy()

    tiers: list[int] = []
    for item in decoded:
        if not isinstance(item, int) or item < 0:
            continue
        if item not in tiers:
            tiers.append(item)
    if 0 not in tiers:
        tiers.insert(0, 0)
    return sorted(tiers) if tiers else DEFAULT_CERTIFIED_CALL_PRICE_TIERS.copy()


async def get_certified_call_price_tiers() -> list[int]:
    raw = await SystemConfig.get_value(
        CERTIFIED_CALL_PRICE_TIERS_KEY,
        json.dumps(DEFAULT_CERTIFIED_CALL_PRICE_TIERS, ensure_ascii=False),
    )
    return parse_certified_call_price_tiers(raw)


async def normalize_certified_call_price(*, price: int, is_certified_user: bool) -> int:
    if not is_certified_user:
        return 0
    tiers = await get_certified_call_price_tiers()
    price_value = int(price)
    if price_value in tiers:
        return price_value
    if 100 in tiers:
        return 100
    paid_tiers = [tier for tier in tiers if tier > 0]
    return paid_tiers[0] if paid_tiers else 0
