from fastapi.routing import APIRoute

from app.core.crud import CRUDBase
from app.log import logger
from app.models.admin import Api
from app.schemas.apis import ApiCreate, ApiUpdate


class ApiController(CRUDBase[Api, ApiCreate, ApiUpdate]):
    def __init__(self):
        super().__init__(model=Api)

    async def refresh_api(self):
        from app import app

        # 收集所有已注册的 API Route
        all_api_list = []
        for route in app.routes:
            if isinstance(route, APIRoute):
                method = list(route.methods - {"HEAD", "OPTIONS"})[0] if (route.methods - {"HEAD", "OPTIONS"}) else None
                path = route.path_format
                if method and path:
                    all_api_list.append((method, path, route.summary, route.tags))

        # 删除数据库中已不存在的 API
        delete_api = []
        for api in await Api.all():
            if (api.method, api.path) not in [(m, p) for m, p, _, _ in all_api_list]:
                delete_api.append((api.method, api.path))
        for method, path in delete_api:
            logger.debug(f"API Deleted {method} {path}")
            await Api.filter(method=method, path=path).delete()

        # 插入或更新 API
        for method, path, summary, tags in all_api_list:
            api_obj = await Api.filter(method=method, path=path).first()
            if api_obj:
                await api_obj.update_from_dict(dict(method=method, path=path, summary=summary, tags=list(tags)[0] if tags else "")).save()
            else:
                logger.debug(f"API Created {method} {path}")
                await Api.create(**dict(method=method, path=path, summary=summary, tags=list(tags)[0] if tags else ""))


api_controller = ApiController()
