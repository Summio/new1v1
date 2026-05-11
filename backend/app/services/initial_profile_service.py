from __future__ import annotations

import json
import random
from typing import Literal

from app.core.redis import get_redis
from app.models.system_config import SYSTEM_CONFIG_CACHE_KEY, SystemConfig
from app.utils.media_url import normalize_media_list, to_relative_media_url

INITIAL_PROFILE_AVATAR_POOL_KEY = "register_avatar_pool"
INITIAL_PROFILE_NICKNAME_POOL_KEY = "register_nickname_pool"
SUPPORTED_GENDERS: tuple[Literal["male", "female"], ...] = ("male", "female")
NICKNAME_SUGGESTION_LIMIT = 12
NICKNAME_PART_MAX_LENGTH = 10


def empty_avatar_pool() -> dict[str, list[str]]:
    return {gender: [] for gender in SUPPORTED_GENDERS}


def empty_nickname_pool() -> dict[str, dict[str, list[str]]]:
    return {gender: {"prefixes": [], "suffixes": []} for gender in SUPPORTED_GENDERS}


def normalize_gender(value: str | None) -> str:
    gender = str(value or "").strip().lower()
    return gender if gender in SUPPORTED_GENDERS else "male"


def normalize_nickname_parts(value: object, *, max_length: int = NICKNAME_PART_MAX_LENGTH) -> list[str]:
    if not isinstance(value, list):
        return []

    out: list[str] = []
    seen: set[str] = set()
    for item in value:
        if not isinstance(item, str):
            continue
        text = item.strip().replace("\r", "").replace("\n", "")
        if not text or len(text) > max_length or text in seen:
            continue
        seen.add(text)
        out.append(text)
    return out


def normalize_nickname_import_item(value: str, *, max_length: int = NICKNAME_PART_MAX_LENGTH) -> str:
    text = str(value or "").strip().replace("\r", "").replace("\n", "")
    if not text:
        return ""

    for prefix in ("输入昵称前缀", "输入昵称后缀", "昵称前缀", "昵称后缀", "前缀", "后缀"):
        if text.startswith(prefix):
            text = text[len(prefix) :].strip()
            break
    if not text:
        return ""
    if len(text) > max_length:
        return ""
    return text


def parse_nickname_import_content(content: str, *, max_length: int = NICKNAME_PART_MAX_LENGTH) -> list[str]:
    rows = str(content or "").replace("、", "\n").replace(",", "\n").replace("，", "\n").splitlines()
    normalized = [normalize_nickname_import_item(item, max_length=max_length) for item in rows]
    return normalize_nickname_parts(normalized, max_length=max_length)


def normalize_avatar_pool(raw: object) -> dict[str, list[str]]:
    if not isinstance(raw, dict):
        return empty_avatar_pool()
    return {gender: normalize_media_list(raw.get(gender)) for gender in SUPPORTED_GENDERS}


def normalize_nickname_pool(raw: object) -> dict[str, dict[str, list[str]]]:
    if not isinstance(raw, dict):
        return empty_nickname_pool()

    out = empty_nickname_pool()
    for gender in SUPPORTED_GENDERS:
        group = raw.get(gender)
        if not isinstance(group, dict):
            continue
        out[gender] = {
            "prefixes": normalize_nickname_parts(group.get("prefixes")),
            "suffixes": normalize_nickname_parts(group.get("suffixes")),
        }
    return out


def build_avatar_candidates(pool: dict[str, list[str]], gender: str) -> list[str]:
    return list(pool.get(normalize_gender(gender), []))


def build_nickname_combinations(pool: dict[str, dict[str, list[str]]], gender: str) -> list[str]:
    group = pool.get(normalize_gender(gender), {})
    prefixes = list(group.get("prefixes", []))
    suffixes = list(group.get("suffixes", []))

    combinations: list[str] = []
    seen: set[str] = set()
    for prefix in prefixes:
        for suffix in suffixes:
            nickname = f"{prefix}{suffix}".strip()
            if not nickname or nickname in seen:
                continue
            seen.add(nickname)
            combinations.append(nickname)
    return combinations


def build_nickname_candidates(
    pool: dict[str, dict[str, list[str]]],
    gender: str,
    *,
    limit: int = NICKNAME_SUGGESTION_LIMIT,
) -> list[str]:
    combinations = build_nickname_combinations(pool, gender)
    if len(combinations) <= limit:
        return combinations
    return random.sample(combinations, limit)


def random_avatar(pool: dict[str, list[str]], gender: str) -> str:
    candidates = build_avatar_candidates(pool, gender)
    if not candidates:
        raise ValueError("当前性别头像池未配置")
    return random.choice(candidates)


def random_nickname(pool: dict[str, dict[str, list[str]]], gender: str) -> str:
    candidates = build_nickname_combinations(pool, gender)
    if not candidates:
        raise ValueError("当前性别昵称池未配置")
    return random.choice(candidates)


def validate_avatar_choice(pool: dict[str, list[str]], gender: str, avatar: str) -> bool:
    normalized = to_relative_media_url(avatar)
    return bool(normalized) and normalized in set(build_avatar_candidates(pool, gender))


def validate_nickname_choice(pool: dict[str, dict[str, list[str]]], gender: str, nickname: str) -> bool:
    normalized = str(nickname or "").strip()
    return bool(normalized) and normalized in set(build_nickname_combinations(pool, gender))


def build_gender_summary(
    avatar_pool: dict[str, list[str]],
    nickname_pool: dict[str, dict[str, list[str]]],
    gender: str,
) -> dict[str, int]:
    gender_key = normalize_gender(gender)
    group = nickname_pool.get(gender_key, {})
    prefixes = list(group.get("prefixes", []))
    suffixes = list(group.get("suffixes", []))
    return {
        "avatar_count": len(avatar_pool.get(gender_key, [])),
        "prefix_count": len(prefixes),
        "suffix_count": len(suffixes),
        "combo_count": len(prefixes) * len(suffixes),
    }


def build_all_summary(
    avatar_pool: dict[str, list[str]],
    nickname_pool: dict[str, dict[str, list[str]]],
) -> dict[str, dict[str, int]]:
    return {gender: build_gender_summary(avatar_pool, nickname_pool, gender) for gender in SUPPORTED_GENDERS}


def build_initial_profile_options(
    avatar_pool: dict[str, list[str]],
    nickname_pool: dict[str, dict[str, list[str]]],
    gender: str,
) -> dict[str, object]:
    gender_key = normalize_gender(gender)
    avatars = build_avatar_candidates(avatar_pool, gender_key)
    selected_avatar = random_avatar(avatar_pool, gender_key) if avatars else ""
    nickname_candidates = build_nickname_combinations(nickname_pool, gender_key)
    selected_nickname = random_nickname(nickname_pool, gender_key) if nickname_candidates else ""
    return {
        "gender": gender_key,
        "selected_avatar": selected_avatar,
        "selected_nickname": selected_nickname,
    }


def _safe_json_loads(value: object) -> object:
    if isinstance(value, (dict, list)):
        return value
    if not isinstance(value, str):
        return None
    text = value.strip()
    if not text:
        return None
    try:
        return json.loads(text)
    except (TypeError, ValueError, json.JSONDecodeError):
        return None


async def load_initial_profile_pool() -> tuple[dict[str, list[str]], dict[str, dict[str, list[str]]]]:
    config_map = await SystemConfig.get_all_as_dict()
    avatar_pool = normalize_avatar_pool(_safe_json_loads(config_map.get(INITIAL_PROFILE_AVATAR_POOL_KEY)))
    nickname_pool = normalize_nickname_pool(_safe_json_loads(config_map.get(INITIAL_PROFILE_NICKNAME_POOL_KEY)))
    return avatar_pool, nickname_pool


async def save_initial_profile_pool(
    *,
    avatar_pool: dict[str, list[str]] | None = None,
    nickname_pool: dict[str, dict[str, list[str]]] | None = None,
) -> None:
    if avatar_pool is not None:
        await _upsert_system_config(
            INITIAL_PROFILE_AVATAR_POOL_KEY,
            json.dumps(normalize_avatar_pool(avatar_pool), ensure_ascii=False),
            description="初始资料头像池配置",
        )
    if nickname_pool is not None:
        await _upsert_system_config(
            INITIAL_PROFILE_NICKNAME_POOL_KEY,
            json.dumps(normalize_nickname_pool(nickname_pool), ensure_ascii=False),
            description="初始资料昵称池配置",
        )
    await clear_system_config_cache()


async def clear_system_config_cache() -> None:
    try:
        redis = await get_redis()
        await redis.delete(SYSTEM_CONFIG_CACHE_KEY)
    except Exception:  # noqa: BLE001
        return


async def _upsert_system_config(cfg_key: str, cfg_value: str, *, description: str) -> None:
    config_obj = await SystemConfig.filter(cfg_key=cfg_key).first()
    if config_obj:
        config_obj.cfg_value = cfg_value
        config_obj.description = description
        await config_obj.save(update_fields=["cfg_value", "description", "updated_at"])
        return
    await SystemConfig.create(cfg_key=cfg_key, cfg_value=cfg_value, description=description)
