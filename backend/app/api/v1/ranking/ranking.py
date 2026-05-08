from fastapi import APIRouter, Query

from app.schemas.base import Fail, Success, SuccessExtra
from app.schemas.ranking import (
    AdminRankingItemOut,
    RankingConfigIn,
    RankingConfigOut,
    RankingMetaOut,
    RankingRefreshIn,
)
from app.services.ranking_service import (
    get_app_display_limit,
    list_admin_ranking,
    refresh_ranking_snapshot,
    set_app_display_limit,
)

router = APIRouter()


@router.get("/list", summary="排行榜列表")
async def ranking_list(
    board: str = Query("charm", description="榜单 charm/wealth/invite"),
    period: str = Query("day", description="周期 day/week/month"),
    page: int = Query(1, ge=1, description="页码"),
    page_size: int = Query(10, ge=1, le=100, description="每页数量"),
    user_id: int | None = Query(None, description="用户ID"),
):
    try:
        rows, total, meta = await list_admin_ranking(
            board,
            period,
            page=page,
            page_size=page_size,
            user_id=user_id,
        )
    except ValueError as exc:
        return Fail(code=400, msg=str(exc))
    data = RankingMetaOut(**meta).model_dump(mode="json")
    items = [AdminRankingItemOut(**row).model_dump(mode="json") for row in rows]
    return SuccessExtra(
        data=data,
        rows=items,
        current=page,
        total=total,
        has_more=page * page_size < total,
    )


@router.post("/refresh", summary="刷新排行榜")
async def ranking_refresh(req_in: RankingRefreshIn):
    try:
        meta = await refresh_ranking_snapshot(req_in.board, req_in.period, force=True)
    except ValueError as exc:
        return Fail(code=400, msg=str(exc))
    return Success(data=RankingMetaOut(**meta).model_dump(mode="json"), msg="刷新成功")


@router.get("/config", summary="排行榜配置")
async def ranking_config_get():
    limit = await get_app_display_limit()
    return Success(data=RankingConfigOut(app_display_limit=limit).model_dump())


@router.put("/config", summary="更新排行榜配置")
async def ranking_config_update(req_in: RankingConfigIn):
    limit = await set_app_display_limit(req_in.app_display_limit)
    return Success(data=RankingConfigOut(app_display_limit=limit).model_dump(), msg="保存成功")
