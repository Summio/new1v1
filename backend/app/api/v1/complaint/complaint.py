from datetime import datetime

from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.core.ctx import CTX_USER_ID
from app.models import AppUser, UserComplaint
from app.schemas.base import Fail, Success, SuccessExtra
from app.schemas.user_complaint import ComplaintHandleIn, ComplaintListItem

router = APIRouter()


async def _complaint_stats(target_user_ids: list[int]) -> dict[int, dict[str, int]]:
    stats = {
        int(user_id): {
            "target_complaint_count": 0,
        }
        for user_id in target_user_ids
    }
    if not target_user_ids:
        return stats
    rows = await UserComplaint.filter(target_user_id__in=target_user_ids).values(
        "target_user_id",
    )
    for row in rows:
        user_id = int(row["target_user_id"])
        item = stats.setdefault(
            user_id,
            {
                "target_complaint_count": 0,
            },
        )
        item["target_complaint_count"] = int(item["target_complaint_count"]) + 1
    return stats


async def _user_map(user_ids: list[int]) -> dict[int, dict]:
    if not user_ids:
        return {}
    users = await AppUser.filter(id__in=user_ids).values("id", "nickname", "phone")
    return {int(row["id"]): row for row in users}


def _build_item(row: UserComplaint, users: dict[int, dict], stats: dict[int, dict[str, int]]) -> dict:
    complainant = users.get(int(row.complainant_id), {})
    target = users.get(int(row.target_user_id), {})
    target_stats = stats.get(int(row.target_user_id), {})
    return ComplaintListItem(
        id=int(row.id),
        complainant_id=int(row.complainant_id),
        target_user_id=int(row.target_user_id),
        reason=row.reason or "",
        content=row.content or "",
        status=row.status or "pending",
        handle_remark=row.handle_remark or "",
        handled_by=int(row.handled_by) if row.handled_by else None,
        handled_at=row.handled_at,
        created_at=row.created_at,
        complainant_nickname=str(complainant.get("nickname") or ""),
        complainant_phone=str(complainant.get("phone") or ""),
        target_nickname=str(target.get("nickname") or ""),
        target_phone=str(target.get("phone") or ""),
        target_complaint_count=int(target_stats.get("target_complaint_count") or 0),
    ).model_dump(mode="json")


@router.get("/list", summary="查看投诉列表")
async def list_complaints(
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    complainant_id: int | None = Query(None, description="投诉人ID"),
    target_user_id: int | None = Query(None, description="被投诉用户ID"),
    status: str = Query("", description="状态"),
    keyword: str = Query("", description="原因或内容关键词"),
    start_time: datetime | None = Query(None, description="提交开始时间"),
    end_time: datetime | None = Query(None, description="提交结束时间"),
):
    q = Q()
    if complainant_id:
        q &= Q(complainant_id=complainant_id)
    if target_user_id:
        q &= Q(target_user_id=target_user_id)
    if status:
        q &= Q(status=status.strip())
    trimmed_keyword = keyword.strip()
    if trimmed_keyword:
        q &= Q(reason__contains=trimmed_keyword) | Q(content__contains=trimmed_keyword)
    if start_time:
        q &= Q(created_at__gte=start_time)
    if end_time:
        q &= Q(created_at__lte=end_time)

    total = await UserComplaint.filter(q).count()
    records = (
        await UserComplaint.filter(q).order_by("-created_at", "-id").offset((page - 1) * page_size).limit(page_size)
    )
    target_ids = list({int(row.target_user_id) for row in records})
    user_ids = list({int(row.complainant_id) for row in records} | set(target_ids))
    stats = await _complaint_stats(target_ids)
    users = await _user_map(user_ids)
    rows = [_build_item(row, users, stats) for row in records]
    return SuccessExtra(data=rows, total=total, page=page, page_size=page_size)


@router.get("/detail", summary="查看投诉详情")
async def complaint_detail(id: int = Query(..., ge=1, description="投诉ID")):
    row = await UserComplaint.filter(id=id).first()
    if not row:
        return Fail(code=404, msg="投诉不存在")
    stats = await _complaint_stats([int(row.target_user_id)])
    users = await _user_map([int(row.complainant_id), int(row.target_user_id)])
    return Success(data=_build_item(row, users, stats))


@router.put("/handle", summary="处理投诉")
async def handle_complaint(req_in: ComplaintHandleIn):
    row = await UserComplaint.filter(id=req_in.id).first()
    if not row:
        return Fail(code=404, msg="投诉不存在")
    await UserComplaint.filter(id=req_in.id).update(
        status=req_in.status,
        handle_remark=req_in.handle_remark.strip() or None,
        handled_by=int(CTX_USER_ID.get() or 0) or None,
        handled_at=datetime.now(),
    )
    return Success(msg="处理成功")
