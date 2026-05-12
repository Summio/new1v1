from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.models import AppUser, CallRecord
from app.schemas.base import Fail, SuccessExtra

router = APIRouter()


def _json_safe(value):
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    return value


def _parse_dt(dt_str: str, field_name: str) -> datetime:
    raw = (dt_str or "").strip()
    if not raw:
        raise ValueError(f"{field_name} 不能为空")
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"{field_name} 格式错误，要求 YYYY-MM-DD HH:mm:ss 或 ISO8601") from exc


@router.get("/list", summary="查看通话记录列表")
async def list_call_record(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    call_id: int | None = Query(None, description="通话ID"),
    user_id: int | None = Query(None, description="用户ID(主叫或被叫)"),
    caller_id: int | None = Query(None, description="主叫用户ID"),
    callee_id: int | None = Query(None, description="被叫用户ID"),
    status: str = Query("", description="状态 pending/ongoing/ended/failed/timeout"),
    end_reason: str = Query("", description="结束原因"),
    start_time: str = Query("", description="开始时间(创建时间起)"),
    end_time: str = Query("", description="结束时间(创建时间止)"),
):
    q = Q()
    if call_id is not None:
        q &= Q(id=call_id)
    if user_id is not None:
        q &= Q(caller_id=user_id) | Q(callee_id=user_id)
    if caller_id is not None:
        q &= Q(caller_id=caller_id)
    if callee_id is not None:
        q &= Q(callee_id=callee_id)
    if status:
        q &= Q(status=status.strip())
    if end_reason:
        q &= Q(end_reason=end_reason.strip())
    try:
        if start_time:
            q &= Q(created_at__gte=_parse_dt(start_time, "start_time"))
        if end_time:
            q &= Q(created_at__lte=_parse_dt(end_time, "end_time"))
    except ValueError as exc:
        return Fail(code=400, msg=str(exc))

    total = await CallRecord.filter(q).count()
    records = await CallRecord.filter(q).order_by("-created_at").offset((page - 1) * page_size).limit(page_size)

    user_ids = list({int(row.caller_id) for row in records} | {int(row.callee_id) for row in records})
    user_map: dict[int, AppUser] = {}
    if user_ids:
        users = await AppUser.filter(id__in=user_ids).all()
        user_map = {int(user.id): user for user in users}

    data = []
    for row in records:
        item = _json_safe(await row.to_dict())
        caller = user_map.get(int(row.caller_id))
        callee = user_map.get(int(row.callee_id))
        item["caller_phone"] = caller.phone if caller else ""
        item["caller_nickname"] = (caller.nickname or caller.phone) if caller else ""
        item["callee_phone"] = callee.phone if callee else ""
        item["callee_nickname"] = (callee.nickname or callee.phone) if callee else ""
        data.append(item)

    return SuccessExtra(data=data, total=total, page=page, page_size=page_size)
