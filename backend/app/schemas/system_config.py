from pydantic import BaseModel, Field


class SystemConfigCreate(BaseModel):
    cfg_key: str = Field(..., description="配置键")
    cfg_value: str = Field(..., description="配置值")
    description: str | None = Field(None, description="说明")


class SystemConfigUpdate(BaseModel):
    id: int = Field(..., description="配置ID")
    cfg_key: str = Field(..., description="配置键")
    cfg_value: str = Field(..., description="配置值")
    description: str | None = Field(None, description="说明")


class SystemConfigOut(BaseModel):
    id: int
    cfg_key: str
    cfg_value: str
    description: str | None
    created_at: str | None
    updated_at: str | None
