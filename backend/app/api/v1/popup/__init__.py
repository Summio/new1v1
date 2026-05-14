from fastapi import APIRouter

from .popup import router

popup_router = APIRouter()
popup_router.include_router(router, tags=["弹窗提示模块"])

__all__ = ["popup_router"]
