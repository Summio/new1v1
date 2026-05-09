"""通话计费相关工具函数"""

from app.models import AppUser, CallRecord


async def resolve_payer_id(call_record: CallRecord) -> int:
    """统一付费方判断逻辑。

    视频通话扣费方规则：
    - 认证用户与非认证用户通话：非认证用户付费
    - 双方都是认证用户：主叫方付费
    - 双方都不是认证用户：不计费，返回 0

    注意：此函数在事务外调用，需要确保调用方处理 TOCTOU 问题。

    Args:
        call_record: 通话记录

    Returns:
        付费方用户 ID，0 表示不计费
    """
    caller_id = int(call_record.caller_id)
    callee_id = int(call_record.callee_id)

    # 单次 IN 查询获取认证用户状态
    users = {int(u.id): bool(u.is_certified_user) for u in await AppUser.filter(id__in=[caller_id, callee_id]).all()}
    caller_is_certified_user = users.get(caller_id, False)
    callee_is_certified_user = users.get(callee_id, False)

    # 认证用户不承担通话费用
    if caller_is_certified_user and not callee_is_certified_user:
        # 认证用户是主叫，非认证用户是被叫 -> 被叫付费
        return callee_id
    if callee_is_certified_user and not caller_is_certified_user:
        # 认证用户是被叫，非认证用户是主叫 -> 主叫付费
        return caller_id
    if caller_is_certified_user and callee_is_certified_user:
        # 双方都是认证用户 -> 主叫方付费，被叫方获得收益
        return caller_id

    # 双方都不是认证用户 -> 不计费
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
