from fastapi import APIRouter, Query

from app.schemas.base import Fail, SuccessExtra
from app.schemas.ranking import AppRankingItemOut, RankingMetaOut
from app.services.ranking_service import list_app_ranking

router = APIRouter()


@router.get("/ranking/list", summary="App排行榜")
async def app_ranking_list(
    board: str = Query("charm", description="榜单 charm/wealth/invite"),
    period: str = Query("day", description="周期 day/week/month"),
):
    try:
        rows, meta = await list_app_ranking(board, period)
    except ValueError as exc:
        return Fail(code=400, msg=str(exc))
    data = RankingMetaOut(**meta).model_dump(mode="json")
    items = [AppRankingItemOut(**row).model_dump(mode="json") for row in rows]
    return SuccessExtra(
        data=data,
        rows=items,
        current=1,
        total=len(items),
        has_more=False,
    )
