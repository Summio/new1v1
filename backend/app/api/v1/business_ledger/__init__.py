from fastapi import APIRouter

from .business_ledger import router

business_ledger_router = APIRouter()
business_ledger_router.include_router(router, tags=["全量业务流水"])

__all__ = ["business_ledger_router"]
