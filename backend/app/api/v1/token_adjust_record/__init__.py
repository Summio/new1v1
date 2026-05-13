from fastapi import APIRouter

from .token_adjust_record import router

token_adjust_record_router = APIRouter()
token_adjust_record_router.include_router(router, tags=["代币修改记录"])

__all__ = ["token_adjust_record_router"]
