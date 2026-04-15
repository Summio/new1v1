from fastapi import APIRouter, Query

from app.schemas.base import Fail, Success

router = APIRouter()


@router.get("/system_config", summary="获取系统配置")
async def get_system_config(
    key: str = Query(None, description="配置键，不传则返回所有配置"),
):
    from app.models.system_config import SystemConfig

    if key:
        cfg = await SystemConfig.filter(cfg_key=key).first()
        if not cfg:
            return Fail(code=404, msg="配置不存在")
        return Success(data={"cfg_key": cfg.cfg_key, "cfg_value": cfg.cfg_value, "description": cfg.description or ""})
    else:
        cfgs = await SystemConfig.all()
        data = {cfg.cfg_key: cfg.cfg_value for cfg in cfgs}
        return Success(data=data)
