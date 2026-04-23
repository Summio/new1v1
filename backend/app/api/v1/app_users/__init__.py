from fastapi import APIRouter

from .app_users import router

app_users_router = APIRouter()
app_users_router.include_router(router, tags=["App用户模块"])

__all__ = ["app_users_router"]
