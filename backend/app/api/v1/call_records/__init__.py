from fastapi import APIRouter

from .call_records import router

call_records_router = APIRouter()
call_records_router.include_router(router, tags=["通话记录模块"])

__all__ = ["call_records_router"]
