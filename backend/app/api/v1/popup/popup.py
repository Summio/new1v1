from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.models import SystemPopup, SystemPopupTask
from app.schemas.base import Fail, Success, SuccessExtra
from app.schemas.system_popup import (
    SystemPopupEstimateIn,
    SystemPopupTaskActionIn,
    SystemPopupTaskCreateIn,
    SystemPopupTaskUpdateIn,
)
from app.services.system_popup_service import (
    POPUP_TYPES,
    REPEAT_TYPES,
    SEND_MODES,
    TARGET_MODES,
    TASK_STATUSES,
    PopupValidationError,
    activate_popup_task,
    count_task_receipts,
    create_popup_task,
    estimate_online_target_count,
    format_popup_datetime,
    normalize_popup_choice,
    recalculate_popup_task_next_run_at,
    validate_popup_task_payload,
)

router = APIRouter()


async def _dump_task(task: SystemPopupTask) -> dict:
    try:
        estimated_count = await estimate_online_target_count(
            target_mode=task.target_mode,
            target_user_ids=task.target_user_ids or [],
            target_filters=task.target_filters or None,
        )
    except PopupValidationError:
        estimated_count = 0
    receipt_counts = await count_task_receipts(task_id=int(task.id))
    run_count = int(task.run_count or 0)
    if task.send_mode == "app_start":
        run_count = await SystemPopup.filter(task_id=task.id).count()
    return {
        "id": int(task.id),
        "title": task.title,
        "content": task.content,
        "type": normalize_popup_choice(task.type, POPUP_TYPES),
        "status": normalize_popup_choice(task.status, TASK_STATUSES),
        "send_mode": normalize_popup_choice(task.send_mode, SEND_MODES),
        "target_mode": normalize_popup_choice(task.target_mode, TARGET_MODES),
        "target_user_ids": task.target_user_ids or [],
        "target_filters": task.target_filters or {},
        "publish_at": format_popup_datetime(task.publish_at),
        "repeat_type": normalize_popup_choice(task.repeat_type, REPEAT_TYPES) or None,
        "repeat_time": task.repeat_time,
        "repeat_weekday": task.repeat_weekday,
        "repeat_month_day": task.repeat_month_day,
        "start_at": format_popup_datetime(task.start_at),
        "end_at": format_popup_datetime(task.end_at),
        "max_runs": task.max_runs,
        "run_count": run_count,
        "next_run_at": format_popup_datetime(task.next_run_at),
        "last_run_at": format_popup_datetime(task.last_run_at),
        "created_at": format_popup_datetime(task.created_at),
        "updated_at": format_popup_datetime(task.updated_at),
        "estimated_count": estimated_count,
        **receipt_counts,
    }


@router.get("/list", summary="弹窗提示任务列表")
async def list_popup_tasks(
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    keyword: str = Query(""),
    type: str = Query(""),
    status: str = Query(""),
    send_mode: str = Query(""),
):
    q = Q()
    if keyword.strip():
        word = keyword.strip()
        q &= Q(title__contains=word) | Q(content__contains=word)
    if type.strip():
        q &= Q(type=type.strip())
    if status.strip():
        q &= Q(status=status.strip())
    if send_mode.strip():
        q &= Q(send_mode=send_mode.strip())
    total = await SystemPopupTask.filter(q).count()
    rows = (
        await SystemPopupTask.filter(q).order_by("-created_at", "-id").offset((page - 1) * page_size).limit(page_size)
    )
    return SuccessExtra(data=[await _dump_task(row) for row in rows], total=total, page=page, page_size=page_size)


@router.get("/get", summary="弹窗提示任务详情")
async def get_popup_task(id: int = Query(..., ge=1)):
    task = await SystemPopupTask.filter(id=id).first()
    if not task:
        return Fail(code=404, msg="弹窗提示不存在")
    return Success(data=await _dump_task(task))


@router.post("/estimate-target-count", summary="预计当前在线可触达人数")
async def estimate_popup_target_count(req_in: SystemPopupEstimateIn):
    try:
        count = await estimate_online_target_count(
            target_mode=req_in.target_mode.value,
            target_user_ids=req_in.target_user_ids,
            target_filters=req_in.target_filters,
        )
    except PopupValidationError as exc:
        return Fail(code=400, msg=str(exc))
    return Success(data={"count": count})


@router.post("/create", summary="创建弹窗提示任务")
async def create_popup(req_in: SystemPopupTaskCreateIn):
    try:
        task = await create_popup_task(req_in.model_dump())
    except PopupValidationError as exc:
        return Fail(code=400, msg=str(exc))
    return Success(data=await _dump_task(task), msg="创建成功")


@router.post("/update", summary="更新弹窗提示任务")
async def update_popup(req_in: SystemPopupTaskUpdateIn):
    task = await SystemPopupTask.filter(id=req_in.id).first()
    if not task:
        return Fail(code=404, msg="弹窗提示不存在")
    if task.status not in {"draft", "scheduled", "paused"}:
        return Fail(code=400, msg="当前状态不可编辑")
    data = req_in.model_dump(exclude={"id"})
    try:
        data = validate_popup_task_payload(data)
    except PopupValidationError as exc:
        return Fail(code=400, msg=str(exc))
    for key, value in data.items():
        setattr(task, key, value)
    await recalculate_popup_task_next_run_at(task)
    return Success(data=await _dump_task(task), msg="更新成功")


@router.post("/publish", summary="发布弹窗提示任务")
async def publish_popup(req_in: SystemPopupTaskActionIn):
    task = await SystemPopupTask.filter(id=req_in.id).first()
    if not task:
        return Fail(code=404, msg="弹窗提示不存在")
    if task.status not in {"draft", "scheduled"}:
        return Fail(code=400, msg="当前状态不可发布")
    try:
        await activate_popup_task(task)
    except PopupValidationError as exc:
        return Fail(code=400, msg=str(exc))
    return Success(data=await _dump_task(task), msg="发布成功")


@router.post("/pause", summary="暂停弹窗提示任务")
async def pause_popup(req_in: SystemPopupTaskActionIn):
    task = await SystemPopupTask.filter(id=req_in.id).first()
    if not task:
        return Fail(code=404, msg="弹窗提示不存在")
    if task.send_mode not in {"repeat", "app_start"} or task.status != "running":
        return Fail(code=400, msg="仅运行中的周期或App启动任务可暂停")
    task.status = "paused"
    await task.save()
    return Success(msg="暂停成功")


@router.post("/resume", summary="恢复弹窗提示任务")
async def resume_popup(req_in: SystemPopupTaskActionIn):
    task = await SystemPopupTask.filter(id=req_in.id).first()
    if not task:
        return Fail(code=404, msg="弹窗提示不存在")
    if task.send_mode not in {"repeat", "app_start"} or task.status != "paused":
        return Fail(code=400, msg="仅暂停中的周期或App启动任务可恢复")
    task.status = "running"
    await recalculate_popup_task_next_run_at(task)
    return Success(data=await _dump_task(task), msg="恢复成功")


@router.post("/cancel", summary="取消弹窗提示任务")
async def cancel_popup(req_in: SystemPopupTaskActionIn):
    task = await SystemPopupTask.filter(id=req_in.id).first()
    if not task:
        return Fail(code=404, msg="弹窗提示不存在")
    if task.status in {"completed", "cancelled"}:
        return Fail(code=400, msg="当前状态不可取消")
    task.status = "cancelled"
    task.next_run_at = None
    await task.save()
    return Success(msg="取消成功")


@router.delete("/delete", summary="删除未发送弹窗提示任务")
async def delete_popup(id: int = Query(..., ge=1)):
    task = await SystemPopupTask.filter(id=id).first()
    if not task:
        return Fail(code=404, msg="弹窗提示不存在")
    sent = await SystemPopup.filter(task_id=id).exists()
    if sent:
        return Fail(code=400, msg="已发送过的弹窗任务不可删除")
    await task.delete()
    return Success(msg="删除成功")
