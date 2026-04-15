from fastapi import APIRouter, Query
from tortoise.expressions import Q

from app.controllers.system_config import system_config_controller
from app.schemas.base import Fail, Success, SuccessExtra
from app.schemas.system_config import SystemConfigCreate, SystemConfigUpdate

router = APIRouter()


@router.get("/list", summary="系统配置列表")
async def list_config(
    page: int = Query(1, description="页码"),
    page_size: int = Query(10, description="每页数量"),
    cfg_key: str = Query("", description="配置键（模糊搜索）"),
):
    q = Q()
    if cfg_key:
        q &= Q(cfg_key__contains=cfg_key)
    total, objs = await system_config_controller.list(page=page, page_size=page_size, search=q)
    data = [await obj.to_dict() for obj in objs]
    return SuccessExtra(data=data, total=total, page=page, page_size=page_size)


@router.get("/get", summary="查看配置")
async def get_config(
    cfg_id: int = Query(..., description="配置ID"),
):
    obj = await system_config_controller.get(id=cfg_id)
    if not obj:
        return Fail(code=404, msg="配置不存在")
    return Success(data=await obj.to_dict())


@router.post("/create", summary="创建配置")
async def create_config(
    config_in: SystemConfigCreate,
):
    existing = await system_config_controller.get_by_key(config_in.cfg_key)
    if existing:
        return Fail(code=400, msg="配置键已存在")
    await system_config_controller.create(obj_in=config_in)
    return Success(msg="Created Successfully")


@router.post("/update", summary="更新配置")
async def update_config(
    config_in: SystemConfigUpdate,
):
    existing = await system_config_controller.get(id=config_in.id)
    if not existing:
        return Fail(code=404, msg="配置不存在")
    # 检查键是否冲突（排除自身）
    conflict = await system_config_controller.get_by_key(config_in.cfg_key)
    if conflict and conflict.id != config_in.id:
        return Fail(code=400, msg="配置键已存在")
    await system_config_controller.update(id=config_in.id, obj_in=config_in)
    return Success(msg="Updated Successfully")


@router.delete("/delete", summary="删除配置")
async def delete_config(
    cfg_id: int = Query(..., description="配置ID"),
):
    await system_config_controller.remove(id=cfg_id)
    return Success(msg="Deleted Successfully")
