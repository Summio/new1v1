from fastapi import APIRouter

from .gift import router

gift_router = APIRouter()
gift_router.include_router(router, tags=["礼物管理"])

__all__ = ["gift_router"]
