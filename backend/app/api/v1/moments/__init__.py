from fastapi import APIRouter

from .moments import router

moments_router = APIRouter()
moments_router.include_router(router, tags=["动态管理"])
