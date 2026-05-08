from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, field_validator

from app.core.app_auth import DependAppAuth
from app.models import AppUser
from app.schemas.base import Fail, Success
from app.utils.password import get_password_hash, verify_password

router = APIRouter()

# 密码正则：至少8位，必须包含字母和数字
_PASSWORD_RE = __import__("re").compile(r"^(?=.*[A-Za-z])(?=.*\d).{8,}$")


class ChangePasswordIn(BaseModel):
    old_password: str
    new_password: str = Field(..., min_length=8, max_length=32)

    @field_validator("new_password")
    @classmethod
    def validate_new_password(cls, v: str) -> str:
        if not _PASSWORD_RE.match(v):
            raise ValueError("密码必须至少8位，且同时包含字母和数字")
        return v


@router.post("/change_password", summary="修改密码")
async def change_password(req_in: ChangePasswordIn, current_user: AppUser = Depends(DependAppAuth)):
    # 校验旧密码
    if not verify_password(req_in.old_password, current_user.password or ""):
        return Fail(code=401, msg="原密码错误")

    # 更新密码
    current_user.password = get_password_hash(req_in.new_password)
    await current_user.save()

    return Success(msg="密码修改成功")
