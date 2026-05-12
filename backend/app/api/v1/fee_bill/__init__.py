from fastapi import APIRouter

from .fee_bill import router

fee_bill_router = APIRouter()
fee_bill_router.include_router(router, tags=["手续费账单"])

__all__ = ["fee_bill_router"]
