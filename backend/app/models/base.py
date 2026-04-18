import asyncio
from datetime import datetime

from tortoise import fields, models

from app.core.time_utils import to_local_naive_for_db
from app.settings import settings


class BaseModel(models.Model):
    id = fields.BigIntField(pk=True, index=True)

    def _normalize_datetime_fields_for_db(self) -> None:
        for field in self._meta.db_fields:
            value = getattr(self, field, None)
            if not isinstance(value, datetime):
                continue
            normalized = to_local_naive_for_db(value)
            if normalized != value:
                setattr(self, field, normalized)

    async def save(self, *args, **kwargs):  # type: ignore[override]
        self._normalize_datetime_fields_for_db()
        return await super().save(*args, **kwargs)

    async def to_dict(self, m2m: bool = False, exclude_fields: list[str] | None = None):
        if exclude_fields is None:
            exclude_fields = []

        d = {}
        for field in self._meta.db_fields:
            if field not in exclude_fields:
                value = getattr(self, field)
                if isinstance(value, datetime):
                    value = value.strftime(settings.DATETIME_FORMAT)
                d[field] = value

        if m2m:
            tasks = [
                self.__fetch_m2m_field(field, exclude_fields)
                for field in self._meta.m2m_fields
                if field not in exclude_fields
            ]
            results = await asyncio.gather(*tasks)
            for field, values in results:
                d[field] = values

        return d

    async def __fetch_m2m_field(self, field, exclude_fields):
        values = await getattr(self, field).all().values()
        formatted_values = []

        for value in values:
            formatted_value = {}
            for k, v in value.items():
                if k not in exclude_fields:
                    if isinstance(v, datetime):
                        formatted_value[k] = v.strftime(settings.DATETIME_FORMAT)
                    else:
                        formatted_value[k] = v
            formatted_values.append(formatted_value)

        return field, formatted_values

    class Meta:
        abstract = True


class UUIDModel:
    uuid = fields.UUIDField(unique=True, pk=False, index=True)


class TimestampMixin:
    created_at = fields.DatetimeField(auto_now_add=True, index=True)
    updated_at = fields.DatetimeField(auto_now=True, index=True)
