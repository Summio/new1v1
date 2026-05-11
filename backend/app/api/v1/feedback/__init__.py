from fastapi import APIRouter

from .feedback import router

feedback_router = APIRouter()
feedback_router.include_router(router, tags=["意见反馈模块"])

__all__ = ["feedback_router"]
