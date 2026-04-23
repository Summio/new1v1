"""通用解析工具函数"""

from typing import Any


def safe_parse_int(raw: Any, default: int) -> int:
    """安全解析整数，支持多种输入格式。

    支持：
    - None -> default
    - int -> 直接返回
    - str -> 去除空格后解析
    - 其他类型 -> 尝试 str 转换后解析

    Args:
        raw: 待解析的值
        default: 解析失败时返回的默认值

    Returns:
        解析后的整数，解析失败时返回 default
    """
    if raw is None:
        return default
    if isinstance(raw, int):
        return raw
    try:
        return int(str(raw).strip())
    except (TypeError, ValueError):
        return default


def safe_parse_bool(raw: Any, default: bool = False) -> bool:
    """安全解析布尔值，支持多种输入格式。

    支持：
    - None -> default
    - bool -> 直接返回
    - int/str -> "1"/"true"/"yes"/"y"/"on" -> True
                 "0"/"false"/"no"/"n"/"off" -> False
                 其他 -> default

    Args:
        raw: 待解析的值
        default: 解析失败时返回的默认值

    Returns:
        解析后的布尔值，解析失败时返回 default
    """
    if raw is None:
        return default
    if isinstance(raw, bool):
        return raw
    normalized = str(raw).strip().lower()
    if normalized in {"1", "true", "yes", "y", "on"}:
        return True
    if normalized in {"0", "false", "no", "n", "off"}:
        return False
    return default


def clamp_int(value: int, min_value: int, max_value: int) -> int:
    """将整数值限制在指定范围内。

    Args:
        value: 待限制的值
        min_value: 最小值
        max_value: 最大值

    Returns:
        限制后的值
    """
    if value < min_value:
        return min_value
    if value > max_value:
        return max_value
    return value
