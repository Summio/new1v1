from datetime import date, datetime

from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.models import AppUser, AppUserTokenAdjustRecord
from app.schemas.base import Fail, SuccessExtra
from app.services.gift_income_service import decimal_to_float_2

router = APIRouter()


def _parse_dt(dt_str: str, field_name: str) -> datetime:
    raw = (dt_str or "").strip()
    if not raw:
        raise ValueError(f"{field_name} 不能为空")
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"{field_name} 格式错误，要求 YYYY-MM-DD HH:mm:ss 或 ISO8601") from exc


def _format_dt(value: datetime | date | None) -> str:
    if not value:
        return ""
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    return value.isoformat()


def _user_brief(user_map: dict[int, AppUser], user_id: int | None) -> dict:
    uid = int(user_id or 0)
    if uid <= 0:
        return {"id": None, "nickname": "", "phone": ""}
    user = user_map.get(uid)
    if not user:
        return {"id": uid, "nickname": f"用户{uid}", "phone": ""}
    return {
        "id": uid,
        "nickname": (user.nickname or user.phone or f"用户{uid}"),
        "phone": user.phone or "",
    }


@router.get("/list", summary="代币修改记录列表")
async def list_token_adjust_record(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    app_user_id: int | None = Query(None, ge=1, description="App用户ID"),
    operator_user_id: int | None = Query(None, ge=1, description="后台操作人ID"),
    asset_type: str = Query("", description="资产类型 coins/diamonds"),
    action: str = Query("", description="调整方向 increase/decrease"),
    start_time: str = Query("", description="开始时间(创建时间起)"),
    end_time: str = Query("", description="结束时间(创建时间止)"),
):
    normalized_asset_type = (asset_type or "").strip()
    if normalized_asset_type and normalized_asset_type not in {"coins", "diamonds"}:
        return Fail(code=400, msg="asset_type 仅支持 coins/diamonds")

    normalized_action = (action or "").strip()
    if normalized_action and normalized_action not in {"increase", "decrease"}:
        return Fail(code=400, msg="action 仅支持 increase/decrease")

    try:
        started_at = _parse_dt(start_time, "start_time") if start_time else None
        ended_at = _parse_dt(end_time, "end_time") if end_time else None
    except ValueError as exc:
        return Fail(code=400, msg=str(exc))

    q = Q()
    if app_user_id is not None:
        q &= Q(app_user_id=app_user_id)
    if operator_user_id is not None:
        q &= Q(operator_user_id=operator_user_id)
    if normalized_asset_type:
        q &= Q(asset_type=normalized_asset_type)
    if normalized_action:
        q &= Q(action=normalized_action)
    if started_at is not None:
        q &= Q(created_at__gte=started_at)
    if ended_at is not None:
        q &= Q(created_at__lte=ended_at)

    total = await AppUserTokenAdjustRecord.filter(q).count()
    records = (
        await AppUserTokenAdjustRecord.filter(q)
        .order_by("-created_at", "-id")
        .offset((page - 1) * page_size)
        .limit(page_size)
    )

    user_ids = {int(row.app_user_id or 0) for row in records}
    users = await AppUser.filter(id__in=list(user_ids)).all() if user_ids else []
    user_map = {int(user.id): user for user in users}

    rows = []
    for row in records:
        rows.append(
            {
                "id": int(row.id),
                "app_user_id": int(row.app_user_id),
                "app_user": _user_brief(user_map, int(row.app_user_id)),
                "operator_user_id": int(row.operator_user_id or 0),
                "operator_username": row.operator_username or "",
                "asset_type": row.asset_type or "",
                "action": row.action or "",
                "amount": decimal_to_float_2(row.amount),
                "before_amount": decimal_to_float_2(row.before_amount),
                "after_amount": decimal_to_float_2(row.after_amount),
                "reason": row.reason or "",
                "created_at": _format_dt(row.created_at),
            }
        )

    return SuccessExtra(
        data=rows,
        total=total,
        page=page,
        page_size=page_size,
        current=page,
        has_more=total > page * page_size,
    )
