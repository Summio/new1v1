from fastapi import APIRouter

from app.core.china_locations import CHINA_PROVINCE_CITY_MAP
from app.schemas.base import Success

router = APIRouter()


@router.get("/location/china", summary="获取中国省市所在地选项")
async def get_china_locations():
    return Success(data=CHINA_PROVINCE_CITY_MAP)
