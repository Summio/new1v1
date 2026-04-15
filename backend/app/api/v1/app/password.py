from fastapi import APIRouter
from pydantic import BaseModel
from app.core.app_auth import DependAppAuth
from app.models import AppUser
from app.schemas.base import Fail, Success
from app.utils.password import verify_password, get_password_hash

router = APIRouter()

class ChangePasswordIn(BaseModel):
    old_password: str
    new_password: str

@router.post('/change_password', summary='修改密码')
async def change_password(req_in: ChangePasswordIn, current_user: AppUser = DependAppAuth):
    # 校验旧密码
    if not verify_password(req_in.old_password, current_user.password or ''):
        return Fail(code=401, msg='原密码错误')
    
    # 更新密码
    current_user.password = get_password_hash(req_in.new_password)
    await current_user.save()
    
    return Success(msg='密码修改成功')
