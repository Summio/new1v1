from datetime import datetime, timedelta, timezone

import jwt
from fastapi import Depends, Header, HTTPException

from app.core.ctx import CTX_APP_USER_ID, CTX_APP_USER_OBJ
from app.models import AppUser
from app.schemas.login import JWTPayload
from app.settings import settings
from app.utils.jwt_utils import create_access_token


class AppAuthControl:
    @classmethod
    async def is_app_authed(cls, token: str = Header(..., description="token")) -> "AppUser":
        try:
            decode_data = jwt.decode(token, settings.SECRET_KEY, algorithms=settings.JWT_ALGORITHM)

            # 检查是否为 App Token
            if not decode_data.get("is_app"):
                raise HTTPException(status_code=401, detail="非App Token")

            user_id = decode_data.get("user_id")
            app_user = await AppUser.filter(id=user_id).first()
            if not app_user:
                raise HTTPException(status_code=401, detail="用户不存在")

            if app_user.status == "banned":
                raise HTTPException(status_code=403, detail=f"账号已被封禁，原因：{app_user.ban_reason or '未知'}")

            CTX_APP_USER_ID.set(int(user_id))
            CTX_APP_USER_OBJ.set(app_user)
            return app_user
        except jwt.DecodeError:
            raise HTTPException(status_code=401, detail="无效的Token")
        except jwt.ExpiredSignatureError:
            raise HTTPException(status_code=401, detail="登录已过期")
        except HTTPException:
            raise
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"{repr(e)}")

    @classmethod
    async def create_app_token(cls, app_user: AppUser, minutes: int = None) -> str:
        if minutes is None:
            minutes = settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES
        expire = datetime.now(timezone.utc) + timedelta(minutes=minutes)
        payload = JWTPayload(
            user_id=app_user.id,
            username=app_user.nickname or app_user.phone,
            is_superuser=False,
            is_app=True,
            exp=expire,
        )
        return create_access_token(data=payload)


DependAppAuth = Depends(AppAuthControl.is_app_authed)
