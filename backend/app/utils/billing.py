"""通话计费相关工具函数"""

from app.models import Anchor, CallRecord


async def resolve_payer_id(call_record: CallRecord) -> int:
    """统一付费方判断逻辑。

    视频通话扣费方规则：非主播方永远付费。
    - 主播（无论主叫还是被叫）不扣费
    - 非主播用户（无论主叫还是被叫）付费
    - 双方都不是主播：主叫方付费（caller_id）
    - 双方都是主播：不计费，返回 0

    注意：此函数在事务外调用，需要确保调用方处理 TOCTOU 问题。

    Args:
        call_record: 通话记录

    Returns:
        付费方用户 ID，0 表示不计费
    """
    caller_id = int(call_record.caller_id)
    callee_id = int(call_record.callee_id)

    # 单次 IN 查询获取主播状态
    anchors = {
        int(a.app_user_id): a
        for a in await Anchor.filter(
            app_user_id__in=[caller_id, callee_id],
            apply_status="approved",
        ).all()
    }
    caller_is_anchor = caller_id in anchors
    callee_is_anchor = callee_id in anchors

    # 主播不承担通话费用
    if caller_is_anchor and not callee_is_anchor:
        # 主播是主叫，非主播是被叫 -> 被叫付费
        return callee_id
    if callee_is_anchor and not caller_is_anchor:
        # 主播是被叫，非主播是主叫 -> 主叫付费
        return caller_id

    # 双方都是主播 -> 不计费
    return 0


def calc_due_minutes(duration_seconds: int, free_seconds_before_billing: int) -> int:
    """计算应扣分钟数（扣除免费秒数）。

    Args:
        duration_seconds: 通话时长（秒）
        free_seconds_before_billing: 免费秒数

    Returns:
        应扣分钟数，不足一分钟按一分钟计
    """
    if duration_seconds < free_seconds_before_billing:
        return 0
    return (duration_seconds + 59) // 60


def next_due_second(deducted_minutes: int, free_seconds_before_billing: int) -> int:
    """计算下次扣费时间点（秒）。

    Args:
        deducted_minutes: 已扣费分钟数
        free_seconds_before_billing: 免费秒数

    Returns:
        下次扣费时间点（秒）
    """
    normalized_deducted = max(0, deducted_minutes)
    if normalized_deducted == 0:
        return free_seconds_before_billing
    return normalized_deducted * 60
