import logging

from fastapi import APIRouter, Body, Query
from tortoise.expressions import Q

from app.controllers.dept import dept_controller
from app.controllers.user import user_controller
from app.schemas.base import Fail, Success, SuccessExtra
from app.schemas.users import *

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/list", summary="查看用户列表")
async def list_user(
    page: int = Query(1, description="页码"),
    page_size: int = Query(10, description="每页数量"),
    username: str = Query("", description="用户名称，用于搜索"),
    email: str = Query("", description="邮箱地址"),
    dept_id: int = Query(None, description="部门ID"),
):
    q = Q()
    if username:
        q &= Q(username__contains=username)
    if email:
        q &= Q(email__contains=email)
    if dept_id is not None:
        q &= Q(dept_id=dept_id)
    total, user_objs = await user_controller.list(page=page, page_size=page_size, search=q)
    data = [await obj.to_dict(m2m=True, exclude_fields=["password"]) for obj in user_objs]
    # 批量查询：一次性获取所有用户的部门，避免 N+1 查询
    dept_ids = {item.get("dept_id") for item in data if item.get("dept_id")}
    dept_map = {}
    if dept_ids:
        depts = await dept_controller.model.filter(id__in=list(dept_ids)).all()
        for dept in depts:
            dept_map[dept.id] = await dept.to_dict()
    for item in data:
        dept_id = item.pop("dept_id", None)
        item["dept"] = dept_map.get(dept_id) or {}

    return SuccessExtra(data=data, total=total, page=page, page_size=page_size)


@router.get("/get", summary="查看用户")
async def get_user(
    user_id: int = Query(..., description="用户ID"),
):
    user_obj = await user_controller.get(id=user_id)
    user_dict = await user_obj.to_dict(exclude_fields=["password"])
    return Success(data=user_dict)


@router.post("/create", summary="创建用户")
async def create_user(
    user_in: UserCreate,
):
    user = await user_controller.get_by_email(user_in.email)
    if user:
        return Fail(code=400, msg="The user with this email already exists in the system.")
    new_user = await user_controller.create_user(obj_in=user_in)
    await user_controller.update_roles(new_user, user_in.role_ids)
    return Success(msg="Created Successfully")


@router.post("/update", summary="更新用户")
async def update_user(
    user_in: UserUpdate,
):
    user = await user_controller.update(id=user_in.id, obj_in=user_in)
    await user_controller.update_roles(user, user_in.role_ids)
    return Success(msg="Updated Successfully")


@router.delete("/delete", summary="删除用户")
async def delete_user(
    user_id: int = Query(..., description="用户ID"),
):
    await user_controller.remove(id=user_id)
    return Success(msg="Deleted Successfully")


@router.post("/reset_password", summary="重置密码")
async def reset_password(user_id: int = Body(..., description="用户ID", embed=True)):
    await user_controller.reset_password(user_id)
    return Success(msg="密码已重置为123456")
