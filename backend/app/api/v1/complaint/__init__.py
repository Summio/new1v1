from fastapi import APIRouter

from .complaint import router

complaint_router = APIRouter()
complaint_router.include_router(router, tags=["投诉管理模块"])

__all__ = ["complaint_router"]
