from typing import Any, Dict, Generic, List, NewType, Tuple, Type, TypeVar, Union

from pydantic import BaseModel
from tortoise.expressions import Q
from tortoise.models import Model

Total = NewType("Total", int)
ModelType = TypeVar("ModelType", bound=Model)
CreateSchemaType = TypeVar("CreateSchemaType", bound=BaseModel)
UpdateSchemaType = TypeVar("UpdateSchemaType", bound=BaseModel)


class CRUDBase(Generic[ModelType, CreateSchemaType, UpdateSchemaType]):
    def __init__(self, model: Type[ModelType]):
        self.model = model

    async def get(self, id: int) -> ModelType:
        return await self.model.get(id=id)

    async def list(
        self, page: int = 1, page_size: int = 20, search: Q = Q(), order: list = []
    ) -> Tuple[Total, List[ModelType]]:
        # 防御性校验：page 和 page_size 必须为正整数
        page = max(1, page)
        page_size = max(1, min(page_size, 100))  # 限制最大单页条数
        query = self.model.filter(search)
        return await query.count(), await query.offset((page - 1) * page_size).limit(page_size).order_by(*order)

    async def create(self, obj_in: CreateSchemaType) -> ModelType:
        if isinstance(obj_in, Dict):
            obj_dict = obj_in
        else:
            obj_dict = obj_in.model_dump()
        obj = self.model(**obj_dict)
        await obj.save()
        return obj

    async def update(self, id: int, obj_in: Union[UpdateSchemaType, Dict[str, Any]]) -> ModelType:
        if isinstance(obj_in, Dict):
            obj_dict = obj_in
        else:
            obj_dict = obj_in.model_dump(exclude_unset=True, exclude={"id"})
        try:
            obj = await self.get(id=id)
        except self.model.DoesNotExist:
            obj = None
        if obj is None:
            raise ValueError(f"{self.model.__name__} with id={id} not found")
        obj = obj.update_from_dict(obj_dict)
        await obj.save()
        return obj

    async def remove(self, id: int) -> None:
        try:
            obj = await self.get(id=id)
        except self.model.DoesNotExist:
            obj = None
        if obj is None:
            raise ValueError(f"{self.model.__name__} with id={id} not found")
        await obj.delete()
